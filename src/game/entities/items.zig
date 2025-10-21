const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Torch = archetype.weapon(.{
    .description = .{ .preset = .torch },
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 20 },
    .source_of_light = .{ .radius = 5 },
    .price = .{ .value = 5 },
    .damage = .{ .damage_type = .blunt, .min = 2, .max = 3 },
    .effect = .{ .effect_type = .burning, .min = 1, .max = 1 },
});

pub const Pickaxe = archetype.weapon(.{
    .description = .{ .preset = .pickaxe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 100 },
    .damage = .{ .damage_type = .cutting, .min = 3, .max = 5 },
    .price = .{ .value = 15 },
});

pub const Club = archetype.weapon(.{
    .description = .{ .preset = .club },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 80 },
    .damage = .{ .damage_type = .blunt, .min = 5, .max = 8 },
    .price = .{ .value = 28 },
});

// The first effect describes the type of the potion
pub const HealingPotion = archetype.potion(.{
    .description = .{ .preset = .healing_potion },
    .sprite = .{ .codepoint = cp.potion },
    .effect = .{ .effect_type = .healing, .min = 20, .max = 25 },
    .weight = .{ .value = 10 },
    .price = .{ .value = 20 },
    .consumable = .{ .consumable_type = .potion, .calories = 10 },
});
