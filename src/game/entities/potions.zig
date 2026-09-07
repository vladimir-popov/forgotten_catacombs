const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;

acid: c.Components = archetype.potion(.{
    .description = .{ .preset = .acid },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 34 },
    .potion = .acid,
}),

antidote: c.Components = archetype.potion(.{
    .description = .{ .preset = .antidote },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 52 },
    .potion = .antidote,
}),

bouillon: c.Components = archetype.potion(.{
    .description = .{ .preset = .bouillon },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 22 },
    .consumable = .{ .calories = 300 },
    .potion = .bouillon,
}),

healing: c.Components = archetype.potion(.{
    .description = .{ .preset = .healing },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 68 },
    .potion = .healing,
}),

liquid_fire: c.Components = archetype.potion(.{
    .description = .{ .preset = .liquid_fire },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 30 },
    .potion = .liquid_fire,
}),

oil: c.Components = archetype.potion(.{
    .description = .{ .preset = .oil },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 14 },
    .potion = .oil,
}),

poison: c.Components = archetype.potion(.{
    .description = .{ .preset = .poison },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 32 },
    .potion = .poison,
}),

spoiled_bouillon: c.Components = archetype.potion(.{
    .description = .{ .preset = .spoiled_bouillon },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 6 },
    .potion = .spoiled_bouillon,
}),

water: c.Components = archetype.potion(.{
    .description = .{ .preset = .water },
    .sprite = .{ .codepoint = cp.potion },
    .price = .{ .value = 4 },
    .potion = .water,
}),
