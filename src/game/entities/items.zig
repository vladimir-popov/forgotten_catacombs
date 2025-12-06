const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

food_ration: c.Components = archetype.food(.{
    .description = .{ .preset = .food_ration },
    .rarity = .common,
    .sprite = .{ .codepoint = cp.food },
    .weight = .{ .value = 50 },
    .price = .{ .value = 50 },
    .consumable = .{ .consumable_type = .food, .calories = 150 },
}),

oil_lamp: c.Components = archetype.item(.{
    .description = .{ .preset = .oil_lamp },
    .rarity = .rare,
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 80 },
    .source_of_light = .{ .radius = 5 },
    .price = .{ .value = 50 },
}),

pub const Armor = struct {
    jacket: c.Components = archetype.armor(.{
        .armor = .init(.{ .physical = 5, .fire = 2 }),
        .description = .{ .preset = .jacket },
        .rarity = .common,
        .sprite = .{ .codepoint = cp.armor },
        .weight = .{ .value = 10 },
        .price = .{ .value = 35 },
    }),
};

pub const Potions = struct {
    healing_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .healing_potion },
        .rarity = .rare,
        .sprite = .{ .codepoint = cp.potion },
        .effect = .{ .effect_type = .healing, .min = 20, .max = 25 },
        .weight = .{ .value = 10 },
        .price = .{ .value = 50 },
        .consumable = .{ .consumable_type = .potion, .calories = 10 },
    }),

    poisoning_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .poisoning_potion },
        .rarity = .rare,
        .sprite = .{ .codepoint = cp.potion },
        .effect = .{ .effect_type = .poisoninig, .min = 20, .max = 25 },
        .weight = .{ .value = 10 },
        .price = .{ .value = 30 },
        .consumable = .{ .consumable_type = .potion, .calories = 0 },
    }),

    oil_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .oil_potion },
        .rarity = .rare,
        .sprite = .{ .codepoint = cp.potion },
        .effect = .{ .effect_type = .poisoninig, .min = 20, .max = 25 },
        .weight = .{ .value = 10 },
        .price = .{ .value = 30 },
        .consumable = .{ .consumable_type = .potion, .calories = 0 },
    }),
};

pub const Weapons = struct {
    club: c.Components = archetype.weapon(.{
        .description = .{ .preset = .club },
        .rarity = .common,
        .sprite = .{ .codepoint = cp.weapon_melee },
        .weight = .{ .value = 80 },
        .damage = .{ .damage_type = .physical, .min = 5, .max = 8 },
        .price = .{ .value = 28 },
        .weapon_class = .primitive,
    }),

    pickaxe: c.Components = archetype.weapon(.{
        .description = .{ .preset = .pickaxe },
        .rarity = .common,
        .sprite = .{ .codepoint = cp.weapon_melee },
        .weight = .{ .value = 100 },
        .damage = .{ .damage_type = .physical, .min = 3, .max = 5 },
        .price = .{ .value = 15 },
        .weapon_class = .primitive,
    }),

    torch: c.Components = archetype.weapon(.{
        .description = .{ .preset = .torch },
        .rarity = .common,
        .sprite = .{ .codepoint = cp.source_of_light },
        .weight = .{ .value = 20 },
        .source_of_light = .{ .radius = 3 },
        .price = .{ .value = 5 },
        .damage = .{ .damage_type = .physical, .min = 2, .max = 3 },
        .effect = .{ .effect_type = .burning, .min = 1, .max = 1 },
        .weapon_class = .primitive,
    }),
};
