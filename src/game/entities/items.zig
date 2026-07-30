const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

torch: c.Components = archetype.weapon(.{
    .description = .{ .preset = .torch },
    .sprite = .{ .codepoint = cp.source_of_light },
    .source_of_light = .{ .radius = 3 },
    .price = .{ .value = 5 },
    .weapon = .meleeWithEffect(.primitive, .range(1, 1), .fire),
}),

oil_lamp: c.Components = archetype.item(.{
    .description = .{ .preset = .oil_lamp },
    .sprite = .{ .codepoint = cp.source_of_light },
    .source_of_light = .{ .radius = 4 },
    .price = .{ .value = 50 },
}),
