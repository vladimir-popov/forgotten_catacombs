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
player: g.Entity,
player_place: p.Point,
player_stats: *const c.Stats,
speed: *const c.Speed,
max_move_points: u8,
environment: Environment,

pub fn passesChance(self: Self, chance_percent: u8) bool {
    return self.environment.passesChanceFn(self.environment.context, chance_percent);
}

pub fn directionToPlayer(self: Self) ?p.Direction {
    return self.environment.directionToPlayerFn(self.environment.context, self.enemy_place);
}

pub fn distanceToPlayer(self: Self) ?u8 {
    return self.environment.distanceToPlayerFn(self.environment.context, self.enemy_place);
}

pub fn isObstacle(self: Self, place: p.Point) bool {
    return self.environment.isObstacleFn(self.environment.context, place);
}

pub fn tryToMove(self: Self, target: g.Action.Payload.Move.Target) ?g.Action {
    return self.environment.tryToMoveFn(self.environment.context, self.enemy_place, target);
}
