//! Callback interface for AI path queries, movement collisions, projectile
//! obstruction checks, and chance rolls. `fromSession` connects these queries
//! to the live level and session PRNG; tests can supply a controlled substitute.
//! Borrows its backing context, which must outlive calls through the interface.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Collision = union(enum) {
    /// The target cell can be entered normally.
    nothing,
    /// A closed door occupies the target cell.
    door: struct { g.Entity, *const c.Door },
    /// Another enemy occupies the target cell.
    enemy: struct { g.Entity, g.Enemy },
    /// A trap occupies the target cell.
    trap: struct { g.Entity, *const c.Trap },
    /// The player occupies the target cell.
    player,
    /// The target cell cannot be entered.
    obstacle,
};

const Self = @This();

context: *anyopaque,

directionToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?p.Direction,
movesToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?u8,
checkCollisionFn: *const fn (context: *anyopaque, from: p.Point, target: g.Action.Payload.Move.Target) Collision,
isObstaclesOnTheLineFn: *const fn (context: *anyopaque, from: p.Point, to: p.Point) bool,
passesChanceFn: *const fn (context: *anyopaque, percent: u8) bool,

/// Creates an environment backed by the current game session and level.
pub fn fromSession(session: *g.GameSession) Self {
    return .{
        .context = session,
        .movesToPlayerFn = movesToPlayer,
        .directionToPlayerFn = directionToPlayer,
        .checkCollisionFn = checkCollision,
        .isObstaclesOnTheLineFn = isObstaclesOnTheLine,
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

pub fn isObstaclesOnTheLine(ptr: *anyopaque, from: p.Point, to: p.Point) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return session.level.isObstaclesOnTheLine(from, to);
}

pub fn passesChance(ptr: *anyopaque, chance_percent: u8) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return session.prng.random().uintLessThan(u8, 100) < chance_percent;
}
