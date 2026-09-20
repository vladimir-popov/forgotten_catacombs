const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;

armadillo_shell_armor: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(3, 5) },
    .description = .{ .preset = .armadillo_shell_armor },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 320 },
}),

cuirass: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(5, 7) },
    .description = .{ .preset = .cuirass },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 430 },
}),

experimental_steam_vest: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(11, 17) },
    .description = .{ .preset = .experimental_steam_vest },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 860 },
}),

galvanized_gilded_cuirass: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(7, 11) },
    .description = .{ .preset = .galvanized_gilded_cuirass },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 620 },
}),

lamellar_armor: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(4, 6) },
    .description = .{ .preset = .lamellar_armor },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 238 },
}),

leather_jerkin: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(1, 2) },
    .description = .{ .preset = .leather_jerkin },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 45 },
}),

riveted_leather_jacket: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(1, 3) },
    .description = .{ .preset = .riveted_leather_jacket },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 78 },
}),

rustplate_coat: c.Components = archetype.armor(.{
    .armor = .{ .protection = .range(2, 4) },
    .description = .{ .preset = .rustplate_coat },
    .sprite = .{ .codepoint = cp.armor },
    .price = .{ .value = 168 },
}),
