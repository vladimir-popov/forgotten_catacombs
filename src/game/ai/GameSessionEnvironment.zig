//! Provides AI world queries backed by a live `GameSession`.
//! Reads player paths and movement collisions from the level, checks projectile
//! obstruction against the level geometry, and uses the session PRNG for chance
//! rolls. Tests use a separate environment implementation instead.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Collision = @import("collision.zig").Collision;

const Self = @This();

session: *g.GameSession,

/// Returns the Dijkstra-map direction from `from` toward the player, or `null`
/// when the player is unreachable from that point.
pub fn directionToPlayer(self: Self, from: p.Point) ?p.Direction {
    return if (self.session.level.dijkstra_map.get(from)) |vector|
        vector.direction
    else
        null;
}

/// Returns the number of Dijkstra-map steps from `from` to the player, or
/// `null` when the player is unreachable from that point.
pub fn movesToPlayer(self: Self, from: p.Point) ?u8 {
    return if (self.session.level.dijkstra_map.get(from)) |vector|
        vector.distance
    else
        null;
}

/// Classifies the cell reached by moving from `from_place` toward `target`.
/// The result distinguishes traversable cells, entities, traps, and obstacles.
pub fn checkCollision(self: Self, from_place: p.Point, target: g.Action.Payload.Move.Target) Collision {
    const place = target.asPlace(from_place);
    if (from_place.eql(place)) return .obstacle;

    switch (self.session.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway) {
            return .nothing;
        },

        .entities => |entities| {
            // Check obstacles
            if (entities[@intFromEnum(c.Position.ZOrder.obstacle)]) |entity| {
                if (entity.eql(self.session.player)) {
                    return .player;
                }

                if (self.session.registry.get(entity, c.Door)) |door| {
                    return .{ .door = .{ entity, door } };
                }

                if (g.meta.getEnemyType(&self.session.registry, entity)) |enemy_type| {
                    return .{ .enemy = .{ entity, enemy_type } };
                }

                return .obstacle;
            }
            // Check traps
            if (entities[@intFromEnum(c.Position.ZOrder.item)]) |entity| {
                if (self.session.registry.get(entity, c.Trap)) |trap| {
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

/// Reports whether a level obstacle intersects the line from `from` to `to`.
pub fn isObstaclesOnTheLine(self: Self, from: p.Point, to: p.Point) bool {
    return self.session.level.isObstaclesOnTheLine(from, to);
}

/// Returns whether a random roll in `[0, 100)` is below `chance_percent`.
pub fn passesChance(self: Self, chance_percent: u8) bool {
    return self.session.prng.random().uintLessThan(u8, 100) < chance_percent;
}
