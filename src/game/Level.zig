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

const Level = @This();

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
map: g.LevelMap,
/// Dijkstra Map of direction to the player. Used to find a path to the player.
dijkstra_map: g.DijkstraMap,
/// The placement where the player right now. It's used for optimization.
player_placement: d.Placement = undefined,

pub fn init(self: *Level, depth: u8, dungeon_seed: u64, session: *g.GameSession) !void {
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
        .map = try g.LevelMap.init(&self.arena, self.dungeon.rows, self.dungeon.cols),
        .dijkstra_map = g.DijkstraMap.init(
            self.arena.allocator(),
            .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
            self.obstacles(),
        ),
    };
    try self.addEntity(session.player);
}

pub fn deinit(self: *Level) void {
    self.arena.deinit();
}

/// Reads json from the reader, deserializes and initializes the level.
pub fn load(self: *Level, session: *g.GameSession, reader: anytype) !void {
    var buffered = std.io.bufferedReader(reader);
    var json_reader = std.json.reader(session.arena.allocator(), buffered.reader());
    defer json_reader.deinit();

    const parsed = try std.json.parseFromTokenSource(g.dto.Level, session.arena.allocator(), &json_reader, .{
        .allocate = .alloc_always,
    });
    defer parsed.deinit();

    try self.init(parsed.value.depth, parsed.value.dungeon_seed, session);
    const alloc = self.arena.allocator();
    for (parsed.value.entities) |entity| {
        try session.entities.copyComponentsToEntity(entity.id, entity.components);
        try self.entities.append(alloc, entity.id);
    }
    try self.addVisitedPlaces(parsed.value.visited_places);
    try self.addRememberedObjects(parsed.value.remembered_objects);
    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;
}

pub fn addVisitedPlaces(self: *Level, visited_places: [][]usize) !void {
    for (visited_places, 0..) |row, row_idx| {
        for (row) |bit| {
            self.map.visited_places[row_idx].set(bit);
        }
    }
}

pub fn addRememberedObjects(self: *Level, remembered_objects: []struct { p.Point, g.Entity }) !void {
    const alloc = self.arena.allocator();
    for (remembered_objects) |kv| {
        try self.map.remembered_objects.put(alloc, kv[0], kv[1]);
    }
}

pub inline fn addEntity(self: *Level, entity: g.Entity) !void {
    try self.entities.append(self.arena.allocator(), entity);
}

pub fn removeEntity(self: *Level, entity: g.Entity) !void {
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
pub fn addEntityAtPlace(self: *Level, item: g.Entity, place: p.Point) !?g.Entity {
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

pub inline fn playerPosition(self: *const Level) *c.Position {
    return self.session.entities.getUnsafe(self.session.player, c.Position);
}

pub inline fn componentsIterator(self: Level) g.ComponentsIterator {
    return self.session.entities.iterator(self.entities.items);
}

pub fn randomEmptyPlace(self: Level, rand: std.Random) ?p.Point {
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

pub fn obstacles(self: *const Level) g.DijkstraMap.Obstacles {
    return .{ .context = self, .isObstacleFn = isObstacleFn };
}

/// This function is used to build the DijkstraMap, that is used to navigate enemies,
/// and to check collision by the walking enemies.
fn isObstacleFn(ptr: *const anyopaque, place: p.Point) bool {
    const self: *const Level = @ptrCast(@alignCast(ptr));
    return isObstacle(self, place);
}

pub fn isObstacle(self: *const Level, place: p.Point) bool {
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
pub fn cellAt(self: Level, place: p.Point) Cell {
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
pub fn itemAt(self: Level, place: p.Point) ?g.Entity {
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
pub fn onPlayerMoved(self: *Level, player_moved: g.events.EntityMoved) !void {
    std.debug.assert(player_moved.is_player);
    self.updatePlacement(player_moved.moved_from, player_moved.targetPlace());
    const player_place = self.playerPosition().place;
    self.dijkstra_map.region.centralizeAround(player_place);
    try self.dijkstra_map.calculate(player_place);
}

fn updatePlacement(self: *Level, player_moved_from: p.Point, player_moved_to: p.Point) void {
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

pub fn generate(self: *Level, depth: u8, session: *g.GameSession, from_ladder: c.Ladder) !void {
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
