const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const cmp = game.components;

pub inline fn Player(universe: *const game.Universe, init_position: p.Point) game.Entity {
    return universe.newEntity()
        .withComponent(cmp.Sprite, .{ .letter = "@" })
        .withComponent(cmp.Position, .{ .point = init_position })
        .withComponent(cmp.Move, .{})
        .entity;
}
