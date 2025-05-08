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

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The list of the entities belong to this level.
// The ArrayList is used instead of HashMap to provide better performance on iterating over items,
// coz it happens more often than lookup the items inside this list.
entities: std.ArrayListUnmanaged(g.Entity),
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
dungeon: d.Dungeon = undefined,
player_placement: d.Placement = undefined,
map: g.LevelMap = undefined,
/// Dijkstra Map to the player
dijkstra_map: g.DijkstraMap = undefined,

pub fn init(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    depth: u8,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
) !Level {
    var arena = std.heap.ArenaAllocator.init(alloc);
    var entities: std.ArrayListUnmanaged(g.Entity) = .empty;
    try entities.append(arena.allocator(), session.player);
    return .{
        .arena = arena,
        .session = session,
        .depth = depth,
        .entities = entities,
        .visibility_strategy = visibility_strategy,
    };
}

pub fn deinit(self: *Level) void {
    self.arena.deinit();
}

pub inline fn addEntity(self: *Level, entity: g.Entity) !void {
    try self.entities.append(self.arena.allocator(), entity);
}

pub inline fn removeEntity(self: *Level, entity: g.Entity) !void {
    try self.session.entities.removeEntity(entity);
    for (0..self.entities.items.len) |idx| {
        if (entity.eql(self.entities.items[idx])) {
            _ = self.entities.swapRemove(idx);
            return;
        }
    }
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

pub const EntitiesOnPositionIterator = struct {
    itr: g.ecs.ComponentsIterator(c.Position),
    place: p.Point,
    next_idx: u8 = 0,

    pub fn next(self: *EntitiesOnPositionIterator) ?g.Entity {
        while (true) {
            if (self.itr.next()) |tuple| {
                if (self.place.eql(tuple[1].point)) return tuple[0];
            } else {
                return null;
            }
        }
    }
};

pub fn entitiesAt(self: Level, place: p.Point) EntitiesOnPositionIterator {
    return .{ .place = place, .entities = self.componentsIterator().of(c.Position) };
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

    var itr = self.componentsIterator().of(c.Position);
    while (itr.next()) |tuple| {
        if (tuple[1].point.eql(place)) {
            if (self.session.entities.get(tuple[0], c.Door)) |door| {
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
