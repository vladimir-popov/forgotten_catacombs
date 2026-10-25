//! Deterministic environment for testing AI without a game session.
//! Path queries return configured values; collision results are looked up by
//! destination point, and projectile obstruction is controlled by a flag.
//! Chance checks succeed exactly when `percent > minimal_percent_to_chance`.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Collision = @import("collision.zig").Collision;

const Self = @This();

/// Fixed Dijkstra-map distance returned for the player, or `null` if unreachable.
moves_to_player: ?u8 = null,
/// Fixed next pathfinding direction toward the player, or `null` if unreachable.
direction_to_player: ?p.Direction = null,
/// Per-destination collision overrides; unspecified destinations are `.nothing`.
collisions: std.AutoHashMapUnmanaged(p.Point, Collision) = .empty,
/// Whether the projectile path between the enemy and player is obstructed.
is_obstacle_in_the_line_of_fire: bool = false,
/// Chance threshold: 0 accepts every positive chance; 100 rejects all chances.
minimal_percent_to_chance: u8 = 100,

/// Returns the configured direction, ignoring the supplied position.
pub fn directionToPlayer(self: Self, _: p.Point) ?p.Direction {
    return self.direction_to_player;
}

/// Returns the configured path distance, ignoring the supplied position.
pub fn movesToPlayer(self: Self, _: p.Point) ?u8 {
    return self.moves_to_player;
}

/// Returns the configured collision at the destination, defaulting to `.nothing`.
pub fn checkCollision(self: Self, from: p.Point, target: g.Action.Payload.Move.Target) Collision {
    const destination = target.asPlace(from);
    return self.collisions.get(destination) orelse .nothing;
}

/// Returns the configured projectile obstruction flag.
pub fn isObstaclesOnTheLine(self: Self, _: p.Point, _: p.Point) bool {
    return self.is_obstacle_in_the_line_of_fire;
}

/// Deterministically accepts the chance only when it exceeds the configured threshold.
pub fn passesChance(self: Self, percent: u8) bool {
    return percent > self.minimal_percent_to_chance;
}
