const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Collision = @import("collision.zig").Collision;

/// Supplies the inputs for one NPC decision without requiring a full game session.
/// `Environment` must provide the follow interface:
/// ```
/// fn passesChance(percent) bool
/// fn directionToPlayer(from) ?Direction
/// fn movesToPlayer(from) ?u8
/// fn checkCollision(from, target) Collision
/// fn isObstaclesOnTheLine(from, to) bool
/// ```
/// The environment type is a `comptime` parameter so calls resolve statically,
/// avoiding runtime indirection while allowing tests to supply a lightweight
/// environment with deterministic responses.
pub fn DecisionContext(comptime Environment: type) type {
    return struct {
        const Self = @This();

        rand: std.Random,
        enemy: g.Entity,
        enemy_place: p.Point,
        enemy_stats: *const c.Stats,
        weapon_range: u8,
        player: g.Entity,
        player_place: p.Point,
        player_stats: *const c.Stats,
        speed: *const c.Speed,
        max_move_points: u8,
        environment: Environment,

        /// Rolls against `chance_percent` using the environment's probability source.
        pub fn passesChance(self: Self, chance_percent: u8) bool {
            return self.environment.passesChance(chance_percent);
        }

        /// Returns the next pathfinding direction toward the player, or `null` when
        /// the player is unreachable from the enemy's position.
        pub fn directionToPlayer(self: Self) ?p.Direction {
            return self.environment.directionToPlayer(self.enemy_place);
        }

        /// Returns the number of Dijkstra-map movement steps to the player, or `null`
        /// when the player is unreachable from the enemy's position.
        pub fn movesToPlayer(self: Self) ?u8 {
            return self.environment.movesToPlayer(self.enemy_place);
        }

        /// Reports whether `place` blocks movement for the enemy.
        pub fn isObstacle(self: Self, place: p.Point) bool {
            return self.environment.isObstacle(place);
        }

        /// Checks what the enemy would encounter by moving toward `target`.
        /// Returns `null` when the target cannot be reached by a single move.
        pub fn checkCollision(self: Self, target: g.Action.Payload.Move.Target) Collision {
            return self.environment.checkCollision(self.enemy_place, target);
        }

        /// Reports whether an obstacle blocks a projectile between `from` and `to`.
        pub fn isObstaclesOnTheLine(self: Self, from: p.Point, to: p.Point) bool {
            return self.environment.isObstaclesOnTheLine(from, to);
        }
    };
}
