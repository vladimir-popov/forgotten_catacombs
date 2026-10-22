//! Supplies the inputs for a single NPC decision without requiring a full session.
//! Holds actor identities, positions, borrowed stats, weapon range, speed, and
//! a move-point budget. World queries and chance checks delegate to `Environment`;
//! `rand` supplies the shuffled direction order used when patrolling.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Environment = @import("Environment.zig");

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
    return self.environment.passesChanceFn(self.environment.context, chance_percent);
}

/// Returns the next pathfinding direction toward the player, or `null` when
/// the player is unreachable from the enemy's position.
pub fn directionToPlayer(self: Self) ?p.Direction {
    return self.environment.directionToPlayerFn(self.environment.context, self.enemy_place);
}

/// Returns the number of Dijkstra-map movement steps to the player, or `null`
/// when the player is unreachable from the enemy's position.
pub fn movesToPlayer(self: Self) ?u8 {
    return self.environment.movesToPlayerFn(self.environment.context, self.enemy_place);
}

/// Reports whether `place` blocks movement for the enemy.
pub fn isObstacle(self: Self, place: p.Point) bool {
    return self.environment.isObstacleFn(self.environment.context, place);
}

/// Checks what the enemy would encounter by moving toward `target`.
/// Returns `null` when the target cannot be reached by a single move.
pub fn checkCollision(self: Self, target: g.Action.Payload.Move.Target) Environment.Collision {
    return self.environment.checkCollisionFn(self.environment.context, self.enemy_place, target);
}

/// Reports whether an obstacle blocks a projectile between `from` and `to`.
pub fn isObstaclesOnTheLine(self: Self, from: p.Point, to: p.Point) bool {
    return self.environment.isObstaclesOnTheLineFn(self.environment.context, from, to);
}
