const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

club: c.Components = archetype.weapon(.{
    .description = .{ .preset = .club },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 42 },
    .weapon = .melee(.primitive, .range(5, 8)),
}),

light_crossbow: c.Components = archetype.weapon(.{
    .description = .{ .preset = .light_crossbow },
    .price = .{ .value = 50 },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .weapon = .ranged(5, .bolts, .primitive, .range(2, 3)),
}),

pickaxe: c.Components = archetype.weapon(.{
    .description = .{ .preset = .pickaxe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 25 },
    .weapon = .melee(.primitive, .range(2, 4)),
}),

poisoned_dagger: c.Components = archetype.weapon(.{
    .description = .{ .preset = .dagger },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 30 },
    .weapon = .meleeWithEffect(.tricky, .range(2, 3), .poison),
}),

short_bow: c.Components = archetype.weapon(.{
    .description = .{ .preset = .short_bow },
    .price = .{ .value = 50 },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .weapon = .ranged(5, .arrows, .tricky, .range(2, 3)),
}),
