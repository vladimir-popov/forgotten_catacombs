const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;

apple: c.Components = archetype.food(.{
    .description = .{ .preset = .apple },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 18 },
    .consumable = .{ .calories = 80 },
}),

dried_fruits: c.Components = archetype.food(.{
    .description = .{ .preset = .dried_fruits },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 20 },
    .consumable = .{ .calories = 90 },
}),

cheese: c.Components = archetype.food(.{
    .description = .{ .preset = .cheese },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 24 },
    .consumable = .{ .calories = 120 },
}),

stale_bread: c.Components = archetype.food(.{
    .description = .{ .preset = .stale_bread },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 24 },
    .consumable = .{ .calories = 140 },
}),

rat_skewer: c.Components = archetype.food(.{
    .description = .{ .preset = .rat_skewer },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 32 },
    .consumable = .{ .calories = 220 },
}),

jerky: c.Components = archetype.food(.{
    .description = .{ .preset = .jerky },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 38 },
    .consumable = .{ .calories = 240 },
}),

sandwich: c.Components = archetype.food(.{
    .description = .{ .preset = .sandwich },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 42 },
    .consumable = .{ .calories = 260 },
}),

stew: c.Components = archetype.food(.{
    .description = .{ .preset = .stew },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 46 },
    .consumable = .{ .calories = 300 },
}),

cooked_meat: c.Components = archetype.food(.{
    .description = .{ .preset = .cooked_meat },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 52 },
    .consumable = .{ .calories = 320 },
}),

tins: c.Components = archetype.food(.{
    .description = .{ .preset = .tins },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 88 },
    .consumable = .{ .calories = 600 },
}),

traveler_ration: c.Components = archetype.food(.{
    .description = .{ .preset = .traveler_ration },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 82 },
    .consumable = .{ .calories = 520 },
}),

salted_meat_pack: c.Components = archetype.food(.{
    .description = .{ .preset = .salted_meat_pack },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 96 },
    .consumable = .{ .calories = 640 },
}),

miners_rations: c.Components = archetype.food(.{
    .description = .{ .preset = .miners_rations },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 102 },
    .consumable = .{ .calories = 680 },
}),

ancient_preserved_supplies: c.Components = archetype.food(.{
    .description = .{ .preset = .ancient_preserved_supplies },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 132 },
    .consumable = .{ .calories = 800 },
}),

insect_paste: c.Components = archetype.food(.{
    .description = .{ .preset = .insect_paste },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 118 },
    .consumable = .{ .calories = 820 },
}),

armadillo_roast: c.Components = archetype.food(.{
    .description = .{ .preset = .armadillo_roast },
    .sprite = .{ .codepoint = cp.food },
    .price = .{ .value = 148 },
    .consumable = .{ .calories = 850 },
}),
