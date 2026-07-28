const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

apple: c.Components = archetype.food(.{
    .description = .{ .preset = .apple },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 10 },
    .consumable = .{ .calories = 350 },
}),

traveler_ration: c.Components = archetype.food(.{
    .description = .{ .preset = .traveler_ration },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 50 },
    .consumable = .{ .calories = 1250 },
}),
