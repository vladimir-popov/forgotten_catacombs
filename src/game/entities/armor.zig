const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

jacket: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(0, 5) },
    .description = .{ .preset = .jacket },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 35 },
}),
