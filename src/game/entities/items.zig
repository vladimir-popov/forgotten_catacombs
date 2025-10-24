const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const preset = g.utils.Preset(c.Components, @This());

pub const Tag = preset.Tag;

pub const count = preset.values.values.len;

pub fn get(tag: Tag) *const c.Components {
    return preset.values.get(tag);
}

pub fn getByIdx(idx: usize) *const c.Components {
    std.debug.assert(idx < count);
    return preset.values.values[idx];
}

pub fn all() preset.Iterator {
    return preset.iterator();
}

club: c.Components = archetype.weapon(.{
    .description = .{ .preset = .club },
    .rarity = .common,
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 80 },
    .damage = .{ .damage_type = .blunt, .min = 5, .max = 8 },
    .price = .{ .value = 28 },
}),

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

oil_potion: c.Components = archetype.potion(.{
    .description = .{ .preset = .oil_potion },
    .rarity = .rare,
    .sprite = .{ .codepoint = cp.potion },
    .effect = .{ .effect_type = .poisoninig, .min = 20, .max = 25 },
    .weight = .{ .value = 10 },
    .price = .{ .value = 30 },
    .consumable = .{ .consumable_type = .potion, .calories = 0 },
}),

pickaxe: c.Components = archetype.weapon(.{
    .description = .{ .preset = .pickaxe },
    .rarity = .common,
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 100 },
    .damage = .{ .damage_type = .cutting, .min = 3, .max = 5 },
    .price = .{ .value = 15 },
}),

torch: c.Components = archetype.weapon(.{
    .description = .{ .preset = .torch },
    .rarity = .common,
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 20 },
    .source_of_light = .{ .radius = 3 },
    .price = .{ .value = 5 },
    .damage = .{ .damage_type = .blunt, .min = 2, .max = 3 },
    .effect = .{ .effect_type = .burning, .min = 1, .max = 1 },
}),

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
