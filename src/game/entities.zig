const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const cmp = game.components;

pub inline fn Player(universe: game.Universe, init_position: p.Point) void {
    _ = universe.newEntity()
        .withComponent(cmp.Sprite, .{ .letter = "@", .position = init_position });
}
