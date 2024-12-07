/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;


const log = std.log.scoped(.level);

const Level = @This();

entities: std.ArrayList(g.Entity),
/// The new new entity id
next_entity: g.Entity = 0,
/// Collection of the components of the entities
components: ecs.ComponentsManager(c.Components),
dungeon: d.Dungeon,
map: g.LevelMap,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The entity id of the player
player: g.Entity = undefined,
player_placement: *const d.Placement = undefined,

pub fn generateFirstLevel(
    self: *Level,
    arena: *std.heap.ArenaAllocator,
    player: c.Components,
    first_time: bool,
) !void {
    self.entities = std.ArrayList(g.Entity).init(arena.allocator());
    self.components = try ecs.ComponentsManager(c.Components).init(arena.allocator());
    self.depth = 0;
    self.dungeon = (try d.FirstLocation.create(arena)).dungeon();
    self.map = try g.LevelMap.init(arena.allocator());

    // Add wharf
    var id = self.newEntity();
    try self.entities.append(id);
    try self.components.setComponentsToEntity(id, g.entities.wharfEntrance(self.dungeon.entrance));

    // Add the ladder leads to the bottom dungeons:
    id = self.newEntity();
    try self.entities.append(id);
    try self.components.setComponentsToEntity(id, g.entities.catacombsEntrance(id, self.dungeon.exit));

    // Generate player on the wharf
    self.player = try self.addNewEntity(player);
    log.debug("The player entity id is {d}", .{self.player});
    if (first_time)
        try self.components.setToEntity(self.player, c.Position{ .point = self.dungeon.entrance })
    else
        try self.components.setToEntity(self.player, c.Position{ .point = self.dungeon.exit });

    // Add the trader
    _ = try self.addNewEntity(g.entities.trader(d.FirstLocation.trader_place));
    // Add the scientist
    _ = try self.addNewEntity(g.entities.scientist(d.FirstLocation.scientist_place));
    // Add the teleport
    _ = try self.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));

    // Add doors
    var doors = self.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.addNewEntity(g.entities.ClosedDoor);
        try self.components.setToEntity(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
    }
    // move player to the entrance
    if (self.dungeon.placementWith(self.dungeon.entrance)) |placement| {
        try self.updatePlacementWithPlayer(placement);
    }
}

/// This methods generates a new level of the catacombs. All fields of the passed level will be overwritten.
pub fn generateCatacomb(
    self: *Level,
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !void {
    self.entities = std.ArrayList(g.Entity).init(arena.allocator());
    self.components = try ecs.ComponentsManager(c.Components).init(arena.allocator());
    self.map = try g.LevelMap.init(arena.allocator());
    self.depth = depth;
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), self.depth, seed, from_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    var bspGenerator = d.BspDungeonGenerator{};
    self.dungeon = try bspGenerator.generateDungeon(arena, prng.random());
    log.debug("The dungeon has been generated", .{});

    self.next_entity = @max(from_ladder.id, from_ladder.target_ladder) + 1;
    // Add ladder by which the player has come to this level first time
    const entrance_place = try self.addLadder(from_ladder.inverted());
    // Generate player on the ladder
    self.player = try self.addNewEntity(player);
    log.debug("The player entity id is {d}", .{self.player});
    try self.components.setToEntity(self.player, c.Position{ .point = entrance_place });
    // Add ladder to the next level
    _ = try self.addLadder(.{
        .direction = from_ladder.direction,
        .id = self.newEntity(),
        .target_ladder = self.newEntity(),
    });

    var doors = self.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.addNewEntity(g.entities.ClosedDoor);
        try self.components.setToEntity(entry.value_ptr.door_id, c.Position{ .point = entry.key_ptr.* });
    }
    // Add enemies
    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try self.addEnemy(prng.random(), g.entities.Rat);
    }
    // move player to the entrance
    if (self.dungeon.placementWith(entrance_place)) |placement| {
        try self.updatePlacementWithPlayer(placement);
    }
}

pub fn generateCave(
    self: *Level,
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    depth: u8,
    player: c.Components,
    from_ladder: c.Ladder,
) !void {
    self.entities = std.ArrayList(g.Entity).init(arena.allocator());
    self.components = try ecs.ComponentsManager(c.Components).init(arena.allocator());
    self.map = try g.LevelMap.init(arena.allocator());
    self.depth = depth;
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any}",
        .{ @tagName(from_ladder.direction), self.depth, seed, from_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    var generator = d.CelluralAutomataGenerator{};
    self.dungeon = try generator.generateDungeon(arena, prng.random());
    log.debug("The dungeon has been generated", .{});

    self.next_entity = @max(from_ladder.id, from_ladder.target_ladder) + 1;
    // Add ladder by which the player has come to this level first time
    const entrance_place = try self.addLadder(from_ladder.inverted());
    // Generate player on the ladder
    self.player = try self.addNewEntity(player);
    log.debug("The player entity id is {d}", .{self.player});
    try self.components.setToEntity(self.player, c.Position{ .point = entrance_place });
    // Add ladder to the next level
    _ = try self.addLadder(.{
        .direction = from_ladder.direction,
        .id = self.newEntity(),
        .target_ladder = self.newEntity(),
    });

    // Add enemies
    // for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
    //     try self.addEnemy(prng.random(), g.entities.Rat);
    // }
    // move player to the entrance
    if (self.dungeon.placementWith(entrance_place)) |placement| {
        try self.updatePlacementWithPlayer(placement);
    }
}

pub fn visibilityStrategy(self: *Level) g.Render.VisibilityStrategy {
    return .{ .context = self, .isVisible = isVisible };
}

pub fn isVisible(ptr: *anyopaque, place: p.Point) g.Render.Visibility {
    const self: *Level = @ptrCast(@alignCast(ptr));
    if (self.player_placement.contains(place))
        return .visible;

    var doorways = self.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (self.dungeon.doorwayAt(door_place.*)) |doorway| {
            // skip the neighbor if the door between is closed
            if (self.components.getForEntityUnsafe(doorway.door_id, c.Door).state == .closed)
                continue;

            if (doorway.oppositePlacement(self.player_placement)) |placement| {
                if (placement.contains(place))
                    return .visible;
            }
        }
    }
    if (self.map.visited_places.isSet(place.row, place.col))
        return .known;

    return .invisible;
}

/// Aggregates requests of few components for the same entities at once
pub fn query(self: *const Level) ecs.ComponentsQuery(c.Components) {
    return .{ .entities = self.entities, .components_manager = self.components };
}

pub fn playerPosition(self: *const Level) *c.Position {
    return self.components.getForEntityUnsafe(self.player, c.Position);
}

pub const EntitiesOnPositionIterator = struct {
    place: p.Point,
    positions: *ecs.ArraySet(c.Position),
    next_idx: u8 = 0,

    pub fn next(self: *EntitiesOnPositionIterator) ?g.Entity {
        while (self.next_idx < self.positions.components.items.len) {
            const idx = self.next_idx;
            self.next_idx +|= 1;
            const place = self.positions.components.items[idx].point;
            if (self.place.eql(place))
                return self.positions.index_entity.get(idx);
        }
        return null;
    }
};

pub fn entityAt(self: Level, place: p.Point) EntitiesOnPositionIterator {
    return .{ .place = place, .positions = self.components.arrayOf(c.Position) };
}

pub fn subscriber(self: *Level) g.events.Subscriber {
    return .{ .context = self, .onEvent = updatePlacement };
}

fn updatePlacement(ptr: *anyopaque, event: g.events.Event) !void {
    if (event.get(.entity_moved) == null) return;
    if (!event.entity_moved.is_player) return;

    const self: *Level = @ptrCast(@alignCast(ptr));
    const entity_moved = event.entity_moved;

    if (self.player_placement.contains(entity_moved.targetPlace())) return;

    if (self.dungeon.doorwayAt(entity_moved.moved_from)) |doorway| {
        if (doorway.oppositePlacement(self.player_placement)) |placement| {
            try self.updatePlacementWithPlayer(placement);
            return;
        }
    }
    if (self.dungeon.placementWith(entity_moved.targetPlace())) |placement| {
        try self.updatePlacementWithPlayer(placement);
        return;
    }
    log.err("It looks like the player is outside of any placement", .{});
}

/// Updates the placement with player and changes visible places
pub fn updatePlacementWithPlayer(self: *Level, placement: *const d.Placement) !void {
    log.debug("New placement with player: {any}", .{placement});
    self.player_placement = placement;
    try self.map.addVisitedPlacement(placement);
    var doorways = self.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (self.dungeon.doorwayAt(door_place.*)) |doorway| {
            if (self.components.getForEntity(doorway.door_id, c.Door)) |door| if (door.state == .opened)
                if (doorway.oppositePlacement(self.player_placement)) |pl| try self.map.addVisitedPlacement(pl);
        }
    }
}

fn addNewEntity(self: *Level, components: c.Components) !g.Entity {
    const entity = self.newEntity();
    try self.entities.append(entity);
    try self.components.setComponentsToEntity(entity, components);
    return entity;
}

fn addLadder(self: *Level, ladder: c.Ladder) !p.Point {
    std.debug.assert(ladder.id < self.next_entity);
    try self.entities.append(ladder.id);
    try self.components.setComponentsToEntity(ladder.id, g.entities.ladder(ladder));
    const place = switch (ladder.direction) {
        .up => self.dungeon.entrance,
        .down => self.dungeon.exit,
    };
    try self.components.setToEntity(ladder.id, c.Position{ .point = place });
    return place;
}

fn addEnemy(self: *Level, rand: std.Random, enemy: c.Components) !void {
    if (self.randomEmptyPlace(rand)) |place| {
        const id = try self.addNewEntity(enemy);
        try self.components.setToEntity(id, c.Position{ .point = place });
    }
}

inline fn newEntity(self: *Level) g.Entity {
    const entity = self.next_entity;
    self.next_entity += 1;
    return entity;
}

pub fn removeEntity(self: *Level, entity: g.Entity) !void {
    try self.components.removeAllForEntity(entity);
    // this is a rare operation, and O(n) here is not as bad, as good the iteration over elements
    // in the array in all other cases
    if (std.mem.indexOfScalar(g.Entity, self.entities.items, entity)) |idx|
        _ = self.entities.swapRemove(idx);
}

const PlaceClarification = union(enum) { anywhere, region: p.Region };

fn randomEmptyPlace(self: *Level, rand: std.Random) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace(rand);
        var is_empty = true;
        var itr = self.query().get(c.Position);
        while (itr.next()) |tuple| {
            if (tuple[1].point.eql(place)) {
                is_empty = false;
            }
        }
        if (is_empty) return place;
    }
    return null;
}
