const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

arrows: c.Components = archetype.ammo(.{
    .ammunition = .arrows(30),
    .description = .{ .preset = .arrows },
    .sprite = .{ .codepoint = cp.ammunition },
    .price = .{ .value = 24 },
}),

bolts: c.Components = archetype.ammo(.{
    .ammunition = .bolts(20),
    .description = .{ .preset = .bolts },
    .sprite = .{ .codepoint = cp.ammunition },
    .price = .{ .value = 20 },
}),

bullets: c.Components = archetype.ammo(.{
    .ammunition = .bullets(10),
    .description = .{ .preset = .bullets },
    .sprite = .{ .codepoint = cp.ammunition },
    .price = .{ .value = 28 },
}),
