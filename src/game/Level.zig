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
/// Dijkstra Map to the player
dijkstra_map: g.DijkstraMap,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The entity id of the player
player: g.Entity = undefined,
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,

pub fn create(
    arena: *std.heap.ArenaAllocator,
    depth: u8,
    dungeon: d.Dungeon,
    player_place: p.Point,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
) !*Level {
    const level = try arena.allocator().create(Level);
    level.* = .{
        .depth = depth,
        .entities = std.ArrayList(g.Entity).init(arena.allocator()),
        .components = try ecs.ComponentsManager(c.Components).init(arena.allocator()),
        .map = try g.LevelMap.init(arena, dungeon.rows, dungeon.cols),
        .dijkstra_map = g.DijkstraMap.init(
            arena.allocator(),
            .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 },
            level.obstacles(),
        ),
        .dungeon = dungeon,
        .player_placement = dungeon.placementWith(player_place).?,
        .visibility_strategy = visibility_strategy,
    };
    return level;
}

pub inline fn checkVisibility(self: *const g.Level, place: p.Point) g.Render.Visibility {
    return self.visibility_strategy(self, place);
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
        const state: c.EnemyState = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
        try level.components.setToEntity(id, state);
    }
}

pub fn randomEmptyPlace(self: Level, rand: std.Random) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace(rand);
        if (self.obstacleAt(place) == null) return place;
    }
    return null;
}

pub fn obstacles(self: *const Level) g.DijkstraMap.Obstacles {
    return .{ .context = self, .isObstacleFn = isObstacle };
}

// TODO improve
fn isObstacle(ptr: *const anyopaque, place: p.Point) bool {
    const self: *const Level = @ptrCast(@alignCast(ptr));
    if (self.obstacleAt(place)) |collision| {
        return switch (collision) {
            .landscape, .door => true,
            else => false,
        };
    }
    return false;
}

// TODO improve
pub fn obstacleAt(
    self: *const Level,
    place: p.Point,
) ?union(enum) { landscape: d.Dungeon.Cell, door: g.Entity, entity: g.Entity } {
    switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => {},
        else => |cell| return .{ .landscape = cell },
    }

    var itr = self.query().get(c.Position);
    while (itr.next()) |tuple| {
        if (tuple[1].point.eql(place)) {
            if (self.components.getForEntity(tuple[0], c.Door)) |door| {
                return if (door.state == .closed) .{ .door = tuple[0] } else null;
            } else {
                return .{ .entity = tuple[0] };
            }
        }
    }
    return null;
}

// The level doesn't subscribe to event directly to avoid unsubscription.
// Instead, the PlayMode delegates events to the actual level.
pub fn onPlayerMoved(self: *Level, player_moved: g.events.EntityMoved) !void {
    std.debug.assert(player_moved.is_player);
    self.updatePlacement(player_moved.moved_from, player_moved.targetPlace());
    const player_place = self.playerPosition().point;
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
