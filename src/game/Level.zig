/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.level);

const Percent = u8;

const Self = @This();

pub const Cell = union(enum) {
    landscape: d.Dungeon.Cell,
    entities: [3]?g.Entity,
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// The list of the entities belong to this level.
/// Used to cleanup global registry on moving from the level.
/// The player doesn't belong to any particular level and should not be presented here.
entities: std.ArrayListUnmanaged(g.Entity),
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8 = undefined,
dungeon: d.Dungeon = undefined,
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility = undefined,
/// Already visited places in the dungeon.
visited_places: []std.DynamicBitSetUnmanaged = undefined,
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMapUnmanaged(p.Point, g.Entity) = .empty,
/// The placement where the player right now. It's used for optimization.
player_placement: d.Placement = undefined,
/// Dijkstra Map of direction to the player. Used to find a path to the player.
dijkstra_map: u.DijkstraMap = undefined,

fn init(self: *Self, session: *g.GameSession) void {
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(session.arena.allocator()),
        .session = session,
        .entities = .empty,
    };
}

fn setupDungeon(self: *Self, depth: u8, dungeon: d.Dungeon) !void {
    log.debug("Setup the dungeon {s} on depth {d}", .{ @tagName(dungeon.type), depth });
    const alloc = self.arena.allocator();
    self.depth = depth;
    self.dungeon = dungeon;
    self.entities.clearRetainingCapacity();
    self.visibility_strategy = switch (dungeon.type) {
        .first_location => g.visibility.showTheCurrentPlacement,
        .cave => g.visibility.showInRadiusOfSourceOfLight,
        .catacomb => if (self.depth < 3)
            g.visibility.showTheCurrentPlacement
        else
            g.visibility.showTheCurrentPlacementInLight,
    };
    self.visited_places = try self.arena.allocator().alloc(std.DynamicBitSetUnmanaged, dungeon.rows);
    self.remembered_objects = std.AutoHashMapUnmanaged(p.Point, g.Entity){};
    self.dijkstra_map = u.DijkstraMap.init(
        self.arena.allocator(),
        .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
        self.obstacles(),
    );
    for (0..self.dungeon.rows) |r0| {
        self.visited_places[r0] = try std.DynamicBitSetUnmanaged.initEmpty(alloc, self.dungeon.cols);
    }
}

fn deinit(self: *Self) void {
    self.arena.deinit();
}

/// Initializes the undefined level as the first level of the game.
pub fn firstLevel(self: *Self, session: *g.GameSession) !void {
    log.debug("Start creating the first level.", .{});

    self.init(session);
    errdefer self.deinit();

    const alloc = self.arena.allocator();

    try self.setupDungeon(0, try d.FirstLocation.generateDungeon(&self.arena));

    // Add wharf
    var entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .floor },
        .description = .{ .preset = .wharf },
        .sprite = .{ .codepoint = cp.ladder_up },
        .position = .{ .place = self.dungeon.entrance },
    });
    try self.entities.append(alloc, entity);

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
    try self.entities.append(alloc, entity);

    // Add the trader
    entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .obstacle },
        .position = .{ .place = d.FirstLocation.trader_place },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
    });
    try self.entities.append(alloc, entity);

    // Add the scientist
    entity = try self.session.entities.addNewEntity(.{
        .z_order = .{ .order = .obstacle },
        .position = .{ .place = d.FirstLocation.scientist_place },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .scientist },
    });
    try self.entities.append(alloc, entity);

    // Add the teleport
    entity = try self.session.entities.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));
    try self.entities.append(alloc, entity);

    // Add doors
    var doors = self.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.session.entities.addNewEntity(g.entities.ClosedDoor);
        try self.session.entities.set(entry.value_ptr.door_id, c.Position{ .place = entry.key_ptr.* });
        try self.entities.append(alloc, entry.value_ptr.door_id);
        log.debug(
            "For the doorway on {any} added closed door with id {d}",
            .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
        );
    }
    try self.completeInitialization(.down);
}

/// Tries to generate a new level with passed seed. In successful case the level
/// will be reinitialized and true returned. Otherwise the level will be not changed
/// and false returned.
pub fn tryGenerateNew(self: *Self, depth: u8, from_ladder: c.Ladder, seed: u64) !bool {
    log.debug(
        "Generate level {s} on depth {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), depth, from_ladder },
    );
    const alloc = self.arena.allocator();

    const dungeon: d.Dungeon = (try self.generateDungeon(depth, seed)) orelse return false;

    try self.setupDungeon(depth, dungeon);

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
            try self.entities.append(alloc, entry.value_ptr.door_id);
            log.debug(
                "For the doorway on {any} added closed door with id {d}",
                .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
            );
        }
    }
    try self.completeInitialization(from_ladder.direction);
    return true;
}

/// Sets up a position for player and remembers the placement with player.
/// This method should be invoked right after setup of a dungeon.
fn completeInitialization(self: *Self, direction: c.Ladder.Direction) !void {
    const init_place = switch (direction) {
        .down => self.dungeon.entrance,
        .up => self.dungeon.exit,
    };
    // Generate player on the ladder
    try self.session.entities.set(self.session.player, c.Position{ .place = init_place });
    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;

    log.debug(
        "The level completed. Depth {d}; seed {d}; type {d}",
        .{ self.depth, self.dungeon.seed, @tagName(self.dungeon.type) },
    );
}

fn generateDungeon(self: *Self, depth: u8, seed: u64) !?d.Dungeon {
    return if (depth == 0)
        try d.FirstLocation.generateDungeon(&self.arena)
    else if (depth < 3)
        try d.Cave.generateDungeon(&self.arena, .{}, seed)
    else
        try d.Catacomb.generateDungeon(&self.arena, .{}, seed);
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
                    try self.entities.append(self.arena.allocator(), pile_id);
                    try self.session.entities.set(pile_id, c.Position{ .place = place });
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
    try self.entities.append(self.arena.allocator(), item);
    return null;
}

pub inline fn checkVisibility(self: *const g.Level, place: p.Point) g.Render.Visibility {
    return self.visibility_strategy(self, place);
}

pub inline fn playerPosition(self: *const Self) *c.Position {
    return self.session.entities.getUnsafe(self.session.player, c.Position);
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

pub fn obstacles(self: *const Self) u.DijkstraMap.Obstacles {
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
    // up to 3 entities with different z-orders may exists at same position
    var result = [3]?g.Entity{ null, null, null };
    var itr = self.session.entities.query2(c.Position, c.ZOrder);
    while (itr.next()) |tuple| {
        const entity, const position, const zorder = tuple;
        const order = @intFromEnum(zorder.order);
        if (position.place.eql(place)) {
            found_entity = true;
            // only one entity with the same order can be at the same place
            if (result[order]) |existed_item| {
                std.debug.panic(
                    "Both items {any} and {any} with order {s} at same place {any}",
                    .{ existed_item, entity, @tagName(zorder.order), place },
                );
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
    var itr = self.session.entities.query2(c.Position, c.ZOrder);
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

fn addLadder(self: *g.Level, ladder: c.Ladder, place: p.Point) !void {
    try self.session.entities.setComponentsToEntity(ladder.id, g.entities.ladder(ladder));
    try self.session.entities.set(ladder.id, c.Position{ .place = place });
    try self.entities.append(self.arena.allocator(), ladder.id);
}

fn addEnemy(self: *g.Level, rand: std.Random, enemy: c.Components) !void {
    if (self.randomEmptyPlace(rand)) |place| {
        const id = try self.session.entities.addNewEntity(enemy);
        try self.session.entities.set(id, c.Position{ .place = place });
        try self.entities.append(self.arena.allocator(), id);
        const state: c.EnemyState = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
        try self.session.entities.set(id, state);
    }
}

const JsonTag = enum {
    depth,
    dungeon_seed,
    entity,
    entities,
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
pub fn load(
    self: *Self,
    session: *g.GameSession,
    reader: g.Runtime.FileReader,
    direction: c.Ladder.Direction,
    progress: Percent,
) !Percent {
    _ = progress;

    self.init(session);
    const alloc = self.arena.allocator();

    var json = std.json.reader(self.arena.allocator(), reader.reader());
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
    const dungeon = (try self.generateDungeon(depth.?, dungeon_seed.?)) orelse {
        log.err("A dungeon was not generate from the saved seed {d}", .{dungeon_seed.?});
        return error.BrokenSeed;
    };
    try self.setupDungeon(depth.?, dungeon);

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
                    try self.entities.append(alloc, entity);
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

    try self.completeInitialization(direction);
    return 100;
}

pub fn save(self: *Self, writer: g.Runtime.FileWriter, progress: Percent) !Percent {
    _ = progress;

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

    return 100;
}

fn assertEql(actual: anytype, expected: anytype) void {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => if (expected != actual) {
            std.debug.panic("Expected {any}, but was {any}", .{ expected, actual });
        },
        else => {},
    }
}
