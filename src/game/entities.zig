const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const cmp = game.components;

pub inline fn Player(universe: *game.Universe, init_position: p.Point) game.Entity {
    const entity = universe.entities.newEntity();
    universe.components.addToEntity(entity, cmp.Sprite, .{ .letter = "@" });
    universe.components.addToEntity(entity, cmp.Position, .{ .point = init_position });
    universe.components.addToEntity(entity, cmp.Move, .{});
    return entity;
}
