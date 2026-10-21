const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Environment = @import("Environment.zig");

distance_to_player: ?u8 = null,
direction_to_player: ?p.Direction = null,
moving_action: ?g.Action = null,
obstacles: []p.Point = &.{},
minimal_percent_to_chance: u8 = 100,

pub fn environment(self: *@This()) Environment {
    return .{
        .context = self,
        .directionToPlayerFn = directionToPlayer,
        .distanceToPlayerFn = distanceToPlayer,
        .isObstacleFn = isObstacle,
        .tryToMoveFn = tryToMove,
        .passesChanceFn = passesChance,
    };
}

fn directionToPlayer(ptr: *anyopaque, _: p.Point) ?p.Direction {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return self.direction_to_player;
}

fn distanceToPlayer(ptr: *anyopaque, _: p.Point) ?u8 {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return self.distance_to_player;
}

fn isObstacle(ptr: *anyopaque, place: p.Point) bool {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    for (self.obstacles) |obstacle| {
        if (obstacle.eql(place))
            return true;
    }
    return false;
}

fn tryToMove(ptr: *anyopaque, _: p.Point, _: g.Action.Payload.Move.Target) ?g.Action {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return self.moving_action;
}

fn passesChance(ptr: *anyopaque, percent: u8) bool {
    const self: *@This() = @ptrCast(@alignCast(ptr));
    return percent > self.minimal_percent_to_chance;
}
