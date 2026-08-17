const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Self = @This();

healing_potion: c.Components = archetype.potion(.{
    .description = .{ .preset = .healing_potion },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 50 },
    .potion = .healing,
}),

poisoning_potion: c.Components = archetype.potion(.{
    .description = .{ .preset = .poisoning_potion },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 30 },
    .potion = .poison,
}),

oil_potion: c.Components = archetype.potion(.{
    .description = .{ .preset = .oil_potion },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 30 },
    .potion = .oil,
}),
