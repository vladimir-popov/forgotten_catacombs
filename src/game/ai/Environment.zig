//! Callback interface for the world queries and chance checks used by AI.
//! Allows behavior rules to use either a live session or a test substitute.
//! The session adapter reads paths, obstacles, and movement interactions from
//! the world and uses the session PRNG for chance checks.
//! Borrows its backing context, which must outlive calls through the interface.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Collision = union(enum) {
    nothing,
    door: struct { g.Entity, *const c.Door },
    enemy: struct { g.Entity, g.Enemy },
    trap: struct { g.Entity, *const c.Trap },
    player,
    obstacle,
};

const Self = @This();

context: *anyopaque,

directionToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?p.Direction,
movesToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?u8,
checkCollisionFn: *const fn (context: *anyopaque, from: p.Point, target: g.Action.Payload.Move.Target) Collision,
passesChanceFn: *const fn (context: *anyopaque, percent: u8) bool,

pub fn fromSession(session: *g.GameSession) Self {
    return .{
        .context = session,
        .movesToPlayerFn = movesToPlayer,
        .directionToPlayerFn = directionToPlayer,
        .checkCollisionFn = checkCollision,
        .passesChanceFn = passesChance,
    };
}

fn directionToPlayer(ptr: *anyopaque, from: p.Point) ?p.Direction {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return if (session.level.dijkstra_map.get(from)) |vector|
        vector.direction
    else
        null;
}

fn movesToPlayer(ptr: *anyopaque, from: p.Point) ?u8 {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return if (session.level.dijkstra_map.get(from)) |vector|
        vector.distance
    else
        null;
}

fn isObstacle(ptr: *anyopaque, place: p.Point) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));

    return session.level.isObstacle(place);
}

fn checkCollision(ptr: *anyopaque, from_place: p.Point, target: g.Action.Payload.Move.Target) Collision {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));

    const place = target.asPlace(from_place);
    if (from_place.eql(place)) return .obstacle;

    switch (session.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway) {
            return .nothing;
        },

        .entities => |entities| {
            // Check obstacles
            if (entities[@intFromEnum(c.Position.ZOrder.obstacle)]) |entity| {
                if (entity.eql(session.player)) {
                    return .player;
                }

                if (session.registry.get(entity, c.Door)) |door| {
                    return .{ .door = .{ entity, door } };
                }

                if (g.meta.getEnemyType(&session.registry, entity)) |enemy_type| {
                    return .{ .enemy = .{ entity, enemy_type } };
                }

                return .obstacle;
            }
            // Check traps
            if (entities[@intFromEnum(c.Position.ZOrder.item)]) |entity| {
                if (session.registry.get(entity, c.Trap)) |trap| {
                    return .{ .trap = .{ entity, trap } };
                }
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with ZOrder.floor
            return .nothing;
        },
    }
    return .obstacle;
}

pub fn passesChance(ptr: *anyopaque, chance_percent: u8) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return session.prng.random().uintLessThan(u8, 100) < chance_percent;
}
