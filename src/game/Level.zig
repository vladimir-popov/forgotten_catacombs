/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;

const log = std.log.scoped(.level);

const Self = @This();

pub const Cell = union(enum) {
    landscape: d.Dungeon.Cell,
    entities: [3]?g.Entity,
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The list of the entities belong to this level.
// The ArrayList is used instead of HashMap to provide better performance on iterating over items,
// coz it happens more often than lookup the items inside this list.
entities: std.ArrayListUnmanaged(g.Entity) = .empty,
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
dungeon: d.Dungeon,
/// Already visited places in the dungeon.
visited_places: []std.DynamicBitSetUnmanaged,
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMapUnmanaged(p.Point, g.Entity),
/// Dijkstra Map of direction to the player. Used to find a path to the player.
dijkstra_map: g.DijkstraMap,
/// The placement where the player right now. It's used for optimization.
player_placement: d.Placement = undefined,

pub fn init(self: *Self, depth: u8, dungeon_seed: u64, session: *g.GameSession) !void {
    const dungeon_type = d.DungeonType.accordingToDepth(depth);
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(session.arena.allocator()),
        .session = session,
        .depth = depth,
        .entities = .empty,
        .dungeon = switch (dungeon_type) {
            .first_location => try d.FirstLocation.generateDungeon(&self.arena),
            .cave => try d.CavesGenerator.generateDungeon(&self.arena, dungeon_seed, .{}),
            .catacomb => try d.CatacombGenerator.generateDungeon(&self.arena, dungeon_seed, .{}),
        },
        .visibility_strategy = switch (dungeon_type) {
            .first_location => g.visibility.showTheCurrentPlacement,
            .cave => g.visibility.showInRadiusOfSourceOfLight,
            .catacomb => if (depth < 3)
                g.visibility.showTheCurrentPlacement
            else
                g.visibility.showTheCurrentPlacementInLight,
        },
        .visited_places = try self.arena.allocator().alloc(std.DynamicBitSetUnmanaged, self.dungeon.rows),
        .remembered_objects = std.AutoHashMapUnmanaged(p.Point, g.Entity){},
        .dijkstra_map = g.DijkstraMap.init(
            self.arena.allocator(),
            .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
            self.obstacles(),
        ),
    };
    const alloc = self.arena.allocator();
    for (0..self.dungeon.rows) |r0| {
        self.visited_places[r0] = try std.DynamicBitSetUnmanaged.initEmpty(alloc, self.dungeon.cols);
    }
    try self.addEntity(session.player);
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

inline fn addEntity(self: *Self, entity: g.Entity) !void {
    try self.entities.append(self.arena.allocator(), entity);
}

pub fn isVisited(self: Self, place: p.Point) bool {
    if (place.row > self.dungeon.rows or place.col > self.dungeon.cols) return false;
    return self.visited_places[place.row - 1].isSet(place.col - 1);
}

pub fn addVisitedPlace(self: *Self, visited_place: p.Point) !void {
    if (visited_place.row > self.dungeon.rows or visited_place.col > self.dungeon.cols) return;
    self.visited_places[visited_place.row - 1].set(visited_place.col - 1);
}

pub fn rememberObject(self: *Self, entity: g.Entity, place: p.Point) !void {
    log.debug("Remember object {any} at {any}", .{ entity, place });
    self.remembered_objects.put(self.arena.allocator(), place, entity);
}

pub fn forgetObject(self: *Self, place: p.Point) !void {
    log.debug("Forget object at {any}", .{place});
    _ = try self.remembered_objects.remove(place);
}

pub fn removeEntity(self: *Self, entity: g.Entity) !void {
    try self.session.entities.removeEntity(entity);
    for (0..self.entities.items.len) |idx| {
        if (entity.eql(self.entities.items[idx])) {
            _ = self.entities.swapRemove(idx);
            return;
        }
    }
}

/// Adds an item to the list of entities on this level, and put it at the place.
/// Three possible scenario can happened here:
///   - If no one other item on the place, then the item will be dropped as is:
///     the position and appropriate sprite will be added to the item;
///   - If some item (not a pile) is on the place, then a new pile
///     will be created and added at the place(a position, zorder and sprite will be added),
///     and both items will be added to that pile;
///   - If a pile is on the place, the item will be added to this pile;
///
/// Returns entity id for the pile if it was created;
pub fn addEntityAtPlace(self: *Self, item: g.Entity, place: p.Point) !?g.Entity {
    switch (self.cellAt(place)) {
        .entities => |entities| {
            // if some item already exists on the place
            if (entities[1]) |entity| {
                // and that item is a pile
                if (self.session.entities.get(entity, c.Pile)) |pile| {
                    log.debug("Adding item {any} into the pile {any} at {any}", .{ item, entity, place });
                    // add a new item to the pile
                    try pile.items.add(item);
                    return entity;
                } else {
                    // or create a new pile and add the item to the pile
                    const pile_id = try self.session.entities.addNewEntityAllocate(g.entities.pile);
                    try self.session.entities.set(pile_id, c.Position{ .place = place });
                    try self.addEntity(pile_id);
                    const pile = self.session.entities.getUnsafe(pile_id, c.Pile);
                    log.debug("Created a pile {any} at {any}", .{ pile_id, place });

                    // add the item to the pile
                    try pile.items.add(item);

                    // move the existed item to the pile
                    try pile.items.add(entity);
                    try self.session.entities.remove(entity, c.Position);
                    return pile_id;
                }
            }
        },
        else => {},
    }
    log.debug("Adding item {any} to the empty place {any}", .{ item, place });
    try self.session.entities.set(item, c.Position{ .place = place });
    try self.addEntity(item);
    return null;
}

pub inline fn checkVisibility(self: *const g.Level, place: p.Point) g.Render.Visibility {
    return self.visibility_strategy(self, place);
}

pub inline fn playerPosition(self: *const Self) *c.Position {
    return self.session.entities.getUnsafe(self.session.player, c.Position);
}

pub inline fn componentsIterator(self: Self) g.ComponentsIterator {
    return self.session.entities.iterator(self.entities.items);
}

pub fn randomEmptyPlace(self: Self, rand: std.Random) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace(rand);
        switch (self.cellAt(place)) {
            .landscape => |landscape| if (landscape == .floor) return place,
            else => return null,
        }
    }
    return null;
}

pub fn obstacles(self: *const Self) g.DijkstraMap.Obstacles {
    return .{ .context = self, .isObstacleFn = isObstacleFn };
}

/// This function is used to build the DijkstraMap, that is used to navigate enemies,
/// and to check collision by the walking enemies.
fn isObstacleFn(ptr: *const anyopaque, place: p.Point) bool {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    return isObstacle(self, place);
}

pub fn isObstacle(self: *const Self, place: p.Point) bool {
    switch (self.cellAt(place)) {
        .landscape => |cl| switch (cl) {
            .floor, .doorway => {},
            else => return true,
        },
        .entities => |entities| if (entities[2]) |entity|
            // an entity with health points is overcoming obstacle
            return self.session.entities.get(entity, c.Health) == null
        else
            // all other are not
            return false,
    }
    return false;
}

/// Returns the cell of the level:
///   - `.landscape` - any kind of the walls or the empty floor/doorway;
///   - `.entities` - an array of the entities on the place:
///       0 - opened doors, ladders, teleports;
///       1 - any dropped items;
///       2 - player, enemies, npc, closed doors;
pub fn cellAt(self: Self, place: p.Point) Cell {
    const landscape = switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => |cl| cl,
        else => |cl| return .{ .landscape = cl },
    };
    // OPTIMIZE IT
    var found_entity = false;
    var result = [3]?g.Entity{ null, null, null };
    var itr = self.componentsIterator().of2(c.Position, c.ZOrder);
    while (itr.next()) |tuple| {
        const entity, const position, const zorder = tuple;
        const order = @intFromEnum(zorder.order);
        if (place.eql(position.place)) {
            found_entity = true;
            // only one entity with the same order can be at the same place
            if (result[order]) |existed_item| {
                std.debug.panic("Both items {any} and {any} at same place {any}", .{ existed_item, entity, place });
            }
            result[order] = entity;
        }
    }
    return if (found_entity) .{ .entities = result } else .{ .landscape = landscape };
}

// OPTIMIZE IT
pub fn itemAt(self: Self, place: p.Point) ?g.Entity {
    switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => {},
        else => return null,
    }
    var itr = self.componentsIterator().of2(c.Position, c.ZOrder);
    while (itr.next()) |tuple| {
        const entity, const position, const zorder = tuple;
        if (place.eql(position.place) and zorder.order == .item) {
            return entity;
        }
    }
    return null;
}

// The level doesn't subscribe to event directly to avoid unsubscription.
// Instead, the PlayMode delegates events to the actual level.
pub fn onPlayerMoved(self: *Self, player_moved: g.events.EntityMoved) !void {
    std.debug.assert(player_moved.is_player);
    self.updatePlacement(player_moved.moved_from, player_moved.targetPlace());
    const player_place = self.playerPosition().place;
    self.dijkstra_map.region.centralizeAround(player_place);
    try self.dijkstra_map.calculate(player_place);
}

fn updatePlacement(self: *Self, player_moved_from: p.Point, player_moved_to: p.Point) void {
    if (self.player_placement.contains(player_moved_to)) return;

    if (self.dungeon.doorwayAt(player_moved_from)) |doorway| {
        if (doorway.oppositePlacement(self.player_placement)) |opposite_placement| {
            if (opposite_placement.contains(player_moved_to)) {
                self.player_placement = opposite_placement;
                log.debug("Placement with player is {any}", .{opposite_placement});
                return;
            }
        }
    }
    if (self.dungeon.placementWith(player_moved_to)) |placement| {
        self.player_placement = placement;
        return;
    }
    log.err("It looks like the player at {any} is outside of any placement", .{player_moved_to});
}

/// Initializes the first level of the game.
pub fn generateFirstLevel(self: *g.Level, session: *g.GameSession) !void {
    log.debug("Begin creation of the first level.", .{});
    try self.init(0, session.seed, session);

    // Add wharf
    var entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .floor },
        .description = .{ .preset = .wharf },
        .sprite = .{ .codepoint = cp.ladder_up },
        .position = .{ .place = self.dungeon.entrance },
    });
    try self.addEntity(entity);

    // Add the ladder leads to the bottom dungeons:
    entity = self.session.entities.newEntity();
    try self.session.entities.setComponentsToEntity(entity, .{
        .z_order = .{ .order = .floor },
        .ladder = .{
            .direction = .down,
            .id = entity,
            .target_ladder = self.session.entities.newEntity(),
        },
        .description = .{ .preset = .ladder_down },
        .sprite = .{ .codepoint = cp.ladder_down },
        .position = .{ .place = self.dungeon.exit },
    });
    try self.addEntity(entity);

    // Place the player on the level
    log.debug("The player entity id is {d}", .{self.session.player.id});
    try self.session.entities.set(self.session.player, c.Position{ .place = self.dungeon.entrance });

    // Add the trader
    entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .obstacle },
        .position = .{ .place = d.FirstLocation.trader_place },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
    });
    try self.addEntity(entity);

    // Add the scientist
    entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .obstacle },
        .position = .{ .place = d.FirstLocation.scientist_place },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .scientist },
    });
    try self.addEntity(entity);

    // Add the teleport
    entity = try self.session.entities.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));
    try self.addEntity(entity);

    // Add doors
    var doors = self.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.session.entities.addNewEntity(g.entities.ClosedDoor);
        try self.addEntity(entry.value_ptr.door_id);
        try self.session.entities.set(entry.value_ptr.door_id, c.Position{ .place = entry.key_ptr.* });
        log.debug(
            "For the doorway on {any} added closed door with id {d}",
            .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
        );
    }
    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;
}

pub fn generate(self: *Self, depth: u8, session: *g.GameSession, from_ladder: c.Ladder) !void {
    log.debug(
        "Generate level {s} on depth {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), depth, from_ladder },
    );
    try self.init(depth, session.seed + depth, session);

    const init_place = switch (from_ladder.direction) {
        .down => self.dungeon.entrance,
        .up => self.dungeon.exit,
    };
    const exit_place = switch (from_ladder.direction) {
        .up => self.dungeon.entrance,
        .down => self.dungeon.exit,
    };
    // Add ladder by which the player has come to this level
    try self.addLadder(from_ladder.inverted(), init_place);
    // Generate player on the ladder
    try self.session.entities.set(self.session.player, c.Position{ .place = init_place });

    // Add ladder to the next level
    try self.addLadder(.{
        .direction = from_ladder.direction,
        .id = self.session.entities.newEntity(),
        .target_ladder = self.session.entities.newEntity(),
    }, exit_place);

    // Add enemies
    const rand = self.session.prng.random();
    for (0..rand.uintLessThan(u8, 10) + 10) |_| {
        try self.addEnemy(rand, g.entities.Rat);
    }

    // Add doors
    if (self.dungeon.doorways) |doorways| {
        var doors = doorways.iterator();
        while (doors.next()) |entry| {
            entry.value_ptr.door_id = try self.session.entities.addNewEntity(g.entities.ClosedDoor);
            try self.session.entities.set(entry.value_ptr.door_id, c.Position{ .place = entry.key_ptr.* });
            try self.addEntity(entry.value_ptr.door_id);
            log.debug(
                "For the doorway on {any} added closed door with id {d}",
                .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
            );
        }
    }

    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;
}

fn addLadder(self: *g.Level, ladder: c.Ladder, place: p.Point) !void {
    try self.session.entities.setComponentsToEntity(ladder.id, g.entities.ladder(ladder));
    try self.session.entities.set(ladder.id, c.Position{ .place = place });
    try self.addEntity(ladder.id);
}

fn addEnemy(self: *g.Level, rand: std.Random, enemy: c.Components) !void {
    if (self.randomEmptyPlace(rand)) |place| {
        const id = try self.session.entities.addNewEntity(enemy);
        try self.addEntity(id);
        try self.session.entities.set(id, c.Position{ .place = place });
        const state: c.EnemyState = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
        try self.session.entities.set(id, state);
    }
}

const JsonTag = enum {
    depth,
    dungeon_seed,
    entities,
    entity,
    place,
    remembered_objects,
    visited_places,

    pub fn writeAsField(self: JsonTag, jws: anytype) !void {
        try jws.objectField(@tagName(self));
    }

    pub fn readFromField(json: anytype) !JsonTag {
        const next = try json.next();
        if (next == .string) {
            return std.meta.stringToEnum(JsonTag, next.string) orelse error.WrongTag;
        } else {
            log.err("Expected a string with tag, but had {any}", .{next});
            return error.WrongTag;
        }
    }
};

/// Reads json from the reader, deserializes and initializes the level.
pub fn load(self: *Self, session: *g.GameSession, reader: g.Runtime.FileReader) !void {
    var buffered = std.io.bufferedReader(reader);
    var json = std.json.reader(session.arena.allocator(), buffered.reader());
    defer json.deinit();

    assertEql(try json.next(), .object_begin);

    // Read the depth and dungeon seed to initialize the level.
    // They have to be the first two fields in the current json object
    var depth: ?u8 = null;
    var dungeon_seed: ?u64 = null;
    var next_tag: JsonTag = undefined;
    while (true) {
        next_tag = try JsonTag.readFromField(&json);
        switch (next_tag) {
            .depth => depth = try std.fmt.parseInt(u8, (try json.next()).number, 10),
            .dungeon_seed => dungeon_seed = try std.fmt.parseInt(u64, (try json.next()).number, 10),
            else => break,
        }
    }
    try self.init(depth.?, dungeon_seed.?, session);
    const alloc = self.arena.allocator();

    // Read other fields and set them to the already initialized level
    loop: while (true) {
        switch (next_tag) {
            .entities => {
                assertEql(try json.next(), .object_begin);
                while (try json.peekNextTokenType() != .object_end) {
                    const entity = g.Entity.parse((try json.next()).string).?;
                    var value = try std.json.Value.jsonParse(alloc, &json, .{ .max_value_len = 1024 });
                    defer value.object.deinit();
                    const parsed_components = try std.json.parseFromValue(c.Components, alloc, value, .{});
                    defer parsed_components.deinit();
                    try self.addEntity(entity);
                    try self.session.entities.copyComponentsToEntity(entity, parsed_components.value);
                }
                std.debug.assert(try json.next() == .object_end);
            },
            .visited_places => {
                assertEql(try json.next(), .array_begin);
                for (0..self.visited_places.len) |i| {
                    var value = try std.json.Value.jsonParse(alloc, &json, .{ .max_value_len = 1024 });
                    defer value.array.deinit();
                    for (value.array.items) |idx| {
                        self.visited_places[i].set(@intCast(idx.integer));
                    }
                }
                assertEql(try json.next(), .array_end);
            },
            .remembered_objects => {
                assertEql(try json.next(), .array_begin);
                while (try json.peekNextTokenType() != .array_end) {
                    var value = try std.json.Value.jsonParse(alloc, &json, .{ .max_value_len = 1024 });
                    defer value.object.deinit();
                    const entity = g.Entity{ .id = @intCast(value.object.get("entity").?.integer) };
                    const place = value.object.get("place").?;
                    try self.remembered_objects.put(alloc, try p.Point.jsonParseFromValue(alloc, place, .{}), entity);
                }
                assertEql(try json.next(), .array_end);
            },
            else => break :loop,
        }
        switch (try json.peekNextTokenType()) {
            .string => {
                next_tag = try JsonTag.readFromField(&json);
            },
            .object_end => {
                _ = try json.next();
                break :loop;
            },
            else => |unexpected| {
                log.err("Unexpected token `{any}`", .{unexpected});
                return error.UnexpectedToken;
            },
        }
    }
    assertEql(try json.next(), .end_of_document);
    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;
}

pub fn save(self: *Self, writer: g.Runtime.FileWriter) !void {
    const alloc = self.arena.allocator();
    var jws = std.json.writeStreamArbitraryDepth(alloc, writer.writer(), .{ .emit_null_optional_fields = false });
    defer jws.deinit();

    try jws.beginObject();
    try JsonTag.depth.writeAsField(&jws);
    try jws.write(self.depth);
    try JsonTag.dungeon_seed.writeAsField(&jws);
    try jws.write(self.dungeon.seed);
    try JsonTag.entities.writeAsField(&jws);
    try jws.beginObject();
    for (self.entities.items) |entity| {
        var buf: [5]u8 = undefined;
        try jws.objectField(try std.fmt.bufPrint(&buf, "{d}", .{entity.id}));
        try jws.write(try self.session.entities.entityToStruct(entity));
    }
    try jws.endObject();
    try JsonTag.visited_places.writeAsField(&jws);
    try jws.beginArray();
    for (self.visited_places) |visited_row| {
        try jws.beginArray();
        var itr = visited_row.iterator(.{});
        while (itr.next()) |idx| {
            try jws.write(idx);
        }
        try jws.endArray();
    }
    try jws.endArray();

    try JsonTag.remembered_objects.writeAsField(&jws);
    var kvs = self.remembered_objects.iterator();
    try jws.beginArray();
    while (kvs.next()) |kv| {
        try jws.beginObject();
        try JsonTag.place.writeAsField(&jws);
        try jws.write(kv.key_ptr.*);
        try JsonTag.entity.writeAsField(&jws);
        try jws.write(kv.value_ptr.id);
        try jws.endObject();
    }
    try jws.endArray();
    try jws.endObject();
}

fn assertEql(actual: anytype, expected: anytype) void {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => if (expected != actual) {
            std.debug.panic("Expected {any}, but was {any}", .{ expected, actual });
        },
        else => {},
    }
}
