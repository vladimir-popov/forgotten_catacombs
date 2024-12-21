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
player_placement: d.Placement,
map: g.LevelMap,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The entity id of the player
player: g.Entity = undefined,
visibility_strategy: g.VisibilityStrategy,

pub fn create(
    arena: *std.heap.ArenaAllocator,
    depth: u8,
    dungeon: d.Dungeon,
    player_place: p.Point,
    visibility_strategy: g.VisibilityStrategy,
) !*Level {
    const level = try arena.allocator().create(Level);
    level.* = .{
        .depth = depth,
        .entities = std.ArrayList(g.Entity).init(arena.allocator()),
        .components = try ecs.ComponentsManager(c.Components).init(arena.allocator()),
        .map = try g.LevelMap.init(arena, dungeon.rows, dungeon.cols),
        .dungeon = dungeon,
        .player_placement = dungeon.placementWith(player_place).?,
        .visibility_strategy = visibility_strategy,
    };
    return level;
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

pub fn addNewEntity(self: *Level, components: c.Components) !g.Entity {
    const entity = self.newEntity();
    try self.entities.append(entity);
    try self.components.setComponentsToEntity(entity, components);
    return entity;
}

pub fn newEntity(self: *Level) g.Entity {
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

pub fn addLadder(self: *Level, ladder: c.Ladder, place: p.Point) !void {
    std.debug.assert(ladder.id < self.next_entity);
    try self.entities.append(ladder.id);
    try self.components.setComponentsToEntity(ladder.id, g.entities.ladder(ladder));
    try self.components.setToEntity(ladder.id, c.Position{ .point = place });
}

pub fn addEnemy(level: *Level, rand: std.Random, enemy: c.Components) !void {
    if (level.randomEmptyPlace(rand)) |place| {
        const id = try level.addNewEntity(enemy);
        try level.components.setToEntity(id, c.Position{ .point = place });
    }
}

pub fn randomEmptyPlace(self: *Level, rand: std.Random) ?p.Point {
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
