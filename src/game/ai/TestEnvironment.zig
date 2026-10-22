//! Configurable `Environment` substitute for testing AI without a game session.
//! Returns fixed path and movement responses and checks a supplied obstacle list.
//! Chance checks succeed only when the percentage exceeds
//! `minimal_percent_to_chance`, making their outcomes deterministic.
//! The returned interface borrows this instance, which must remain alive in place.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Environment = @import("Environment.zig");

moves_to_player: ?u8 = null,
direction_to_player: ?p.Direction = null,
collisions: std.AutoHashMapUnmanaged(p.Point, Environment.Collision) = .empty,
/// 0 makes every positive chance succeed; 100 makes every valid chance fail.
minimal_percent_to_chance: u8 = 100,

pub fn environment(self: *@This()) Environment {
    return .{
        .context = self,
        .directionToPlayerFn = directionToPlayer,
        .movesToPlayerFn = movesToPlayer,
        .checkCollisionFn = checkCollision,
        .passesChanceFn = passesChance,
    };
}

fn directionToPlayer(ptr: *anyopaque, _: p.Point) ?p.Direction {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return self.direction_to_player;
}

fn movesToPlayer(ptr: *anyopaque, _: p.Point) ?u8 {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return self.moves_to_player;
}

fn checkCollision(ptr: *anyopaque, from: p.Point, target: g.Action.Payload.Move.Target) Environment.Collision {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    const destination = target.asPlace(from);
    return self.collisions.get(destination) orelse .nothing;
}

fn passesChance(ptr: *anyopaque, percent: u8) bool {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return percent > self.minimal_percent_to_chance;
}
