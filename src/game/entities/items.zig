const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

oil_lamp: c.Components = archetype.item(.{
    .description = .{ .preset = .oil_lamp },
    .rarity = .rare,
    .tier = .{ .value = 0 },
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 80 },
    .source_of_light = .{ .radius = 4 },
    .price = .{ .value = 50 },
}),

pub const Armor = struct {
    jacket: c.Components = archetype.armor(.{
        .protection = .init(.{ .physical = .range(0, 5), .fire = .range(0, 2) }),
        .description = .{ .preset = .jacket },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.armor },
        .weight = .{ .value = 10 },
        .price = .{ .value = 35 },
    }),
};

pub const Weapons = struct {
    arrows: c.Components = archetype.ammo(.{
        .ammunition = .arrows(10),
        .description = .{ .preset = .arrows },
        .rarity = .common,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.ammunition },
        .weight = .{ .value = 10 },
        .price = .{ .value = 10 },
    }),

    bolts: c.Components = archetype.ammo(.{
        .ammunition = .bolts(10),
        .description = .{ .preset = .bolts },
        .rarity = .common,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.ammunition },
        .weight = .{ .value = 10 },
        .price = .{ .value = 10 },
    }),

    club: c.Components = archetype.weapon(.{
        .description = .{ .preset = .club },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.weapon_melee },
        .weight = .{ .value = 80 },
        .price = .{ .value = 28 },
        .weapon = .melee(.primitive, .effects(.{ .physical = .range(5, 8) })),
    }),

    light_crossbow: c.Components = archetype.weapon(.{
        .description = .{ .preset = .light_crossbow },
        .price = .{ .value = 50 },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.weapon_ranged },
        .weapon = .ranged(5, .bolts, .primitive, .effects(.{ .physical = .range(2, 3) })),
        .weight = .{ .value = 70 },
    }),

    pickaxe: c.Components = archetype.weapon(.{
        .description = .{ .preset = .pickaxe },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.weapon_melee },
        .weight = .{ .value = 100 },
        .price = .{ .value = 15 },
        .weapon = .melee(.primitive, .effects(.{ .physical = .range(5, 9) })),
    }),

    torch: c.Components = archetype.weapon(.{
        .description = .{ .preset = .torch },
        .rarity = .common,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.source_of_light },
        .weight = .{ .value = 20 },
        .source_of_light = .{ .radius = 3 },
        .price = .{ .value = 5 },
        .weapon = .melee(.primitive, .effects(.{ .physical = .range(1, 1), .fire = .range(1, 1) })),
    }),

    poisoned_dagger: c.Components = archetype.weapon(.{
        .description = .{ .preset = .dagger },
        .rarity = .rare,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.weapon_melee },
        .weight = .{ .value = 50 },
        .price = .{ .value = 50 },
        .weapon = .melee(.tricky, .effects(.{ .physical = .range(2, 3), .poison = .range(1, 3) })),
    }),

    short_bow: c.Components = archetype.weapon(.{
        .description = .{ .preset = .short_bow },
        .price = .{ .value = 50 },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.weapon_ranged },
        .weapon = .ranged(5, .arrows, .tricky, .effects(.{ .physical = .range(2, 3) })),
        .weight = .{ .value = 50 },
    }),
};

pub const Food = struct {
    apple: c.Components = archetype.food(.{
        .description = .{ .preset = .apple },
        .rarity = .common,
        .tier = .{ .value = 1 },
        .sprite = .{ .codepoint = cp.food },
        .weight = .{ .value = 5 },
        .price = .{ .value = 10 },
        .consumable = .{ .consumable_type = .food, .calories = 350 },
    }),

    food_ration: c.Components = archetype.food(.{
        .description = .{ .preset = .food_ration },
        .rarity = .common,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.food },
        .weight = .{ .value = 50 },
        .price = .{ .value = 50 },
        .consumable = .{ .consumable_type = .food, .calories = 1250 },
    }),
};

pub const Potions = struct {
    healing_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .healing_potion },
        .rarity = .rare,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.potion },
        .weight = .{ .value = 10 },
        .price = .{ .value = 50 },
        .consumable = .potion(.{ .heal = .range(20, 25) }, 50),
    }),

    poisoning_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .poisoning_potion },
        .rarity = .rare,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.potion },
        .weight = .{ .value = 10 },
        .price = .{ .value = 30 },
        .consumable = .potion(.{ .poison = .range(10, 20) }, 10),
    }),

    oil_potion: c.Components = archetype.potion(.{
        .description = .{ .preset = .oil_potion },
        .rarity = .rare,
        .tier = .{ .value = 0 },
        .sprite = .{ .codepoint = cp.potion },
        .weight = .{ .value = 10 },
        .price = .{ .value = 30 },
        .consumable = .potion(.{ .poison = .range(20, 25) }, 100),
    }),
};
