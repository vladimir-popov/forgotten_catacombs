const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;

baseball_bat: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .baseball_bat },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 42 },
    .weapon = .melee(.primitive, .range(2, 6)),
}),

cane_sword: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 5 },
    .description = .{ .preset = .cane_sword },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 420 },
    .weapon = .melee(.ancient, .range(13, 27)),
}),

cavalry_saber: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 5 },
    .description = .{ .preset = .cavalry_saber },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 330 },
    .weapon = .melee(.tricky, .range(11, 21)),
}),

crude_axe: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 3 },
    .description = .{ .preset = .crude_axe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 102 },
    .weapon = .melee(.primitive, .range(4, 14)),
}),

dagger: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .dagger },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 40 },
    .weapon = .melee(.tricky, .range(1, 5)),
}),

double_barrel_shotgun: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 7 },
    .description = .{ .preset = .double_barrel_shotgun },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 980 },
    .weapon = .ranged(.primitive, .range(19, 37), 4, .bullets),
}),

entrenching_tool: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 4 },
    .description = .{ .preset = .entrenching_tool },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 260 },
    .weapon = .melee(.tricky, .range(5, 17)),
}),

flintlock_musket: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .flintlock_musket },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 700 },
    .weapon = .ranged(.primitive, .range(8, 24), 5, .bullets),
}),

flintlock_pistol: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 5 },
    .description = .{ .preset = .flintlock_pistol },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 360 },
    .weapon = .ranged(.tricky, .range(5, 11), 5, .bullets),
}),

gas_sprayer: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 8 },
    .description = .{ .preset = .gas_sprayer },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 1080 },
    .weapon = .meleeWithEffect(.ancient, .range(45, 91), .poison),
}),

hand_crossbow: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .hand_crossbow },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 96 },
    .weapon = .ranged(.primitive, .range(2, 6), 4, .bolts),
}),

hatchet: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .hatchet },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 54 },
    .weapon = .melee(.primitive, .range(4, 8)),
}),

heavy_crossbow: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 4 },
    .description = .{ .preset = .heavy_crossbow },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 210 },
    .weapon = .ranged(.primitive, .range(3, 11), 5, .bolts),
}),

heavy_saber: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 7 },
    .description = .{ .preset = .heavy_saber },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 820 },
    .weapon = .melee(.primitive, .range(23, 69)),
}),

hunting_bow: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 3 },
    .description = .{ .preset = .hunting_bow },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 110 },
    .weapon = .ranged(.tricky, .range(2, 6), 5, .arrows),
}),

hunting_rifle: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .hunting_rifle },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 520 },
    .weapon = .ranged(.tricky, .range(7, 15), 6, .bullets),
}),

iron_mace: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 3 },
    .description = .{ .preset = .iron_mace },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 118 },
    .weapon = .melee(.primitive, .range(4, 14)),
}),

katana: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 4 },
    .description = .{ .preset = .katana },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 176 },
    .weapon = .melee(.tricky, .range(7, 15)),
}),

long_sword: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 4 },
    .description = .{ .preset = .long_sword },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 148 },
    .weapon = .melee(.primitive, .range(9, 19)),
}),

machete: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .machete },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 390 },
    .weapon = .melee(.tricky, .range(16, 32)),
}),

nagant_revolver: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .nagant_revolver },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 640 },
    .weapon = .ranged(.ancient, .range(11, 21), 5, .bullets),
}),

naval_dirk: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 5 },
    .description = .{ .preset = .naval_dirk },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 270 },
    .weapon = .melee(.tricky, .range(8, 24)),
}),

nunchaku: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 3 },
    .description = .{ .preset = .nunchaku },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 126 },
    .weapon = .melee(.tricky, .range(5, 9)),
}),

officers_rapier: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 7 },
    .description = .{ .preset = .officers_rapier },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 860 },
    .weapon = .melee(.tricky, .range(24, 48)),
}),

officers_sword: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .officers_sword },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 460 },
    .weapon = .melee(.primitive, .range(20, 40)),
}),

pickaxe: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .pickaxe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 18 },
    .weapon = .melee(.primitive, .range(2, 6)),
}),

poison_dagger: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .poison_dagger },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 74 },
    .weapon = .meleeWithEffect(.tricky, .range(3, 7), .poison),
}),

rapier: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 3 },
    .description = .{ .preset = .rapier },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 84 },
    .weapon = .melee(.tricky, .range(5, 9)),
}),

riot_baton: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 5 },
    .description = .{ .preset = .riot_baton },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 248 },
    .weapon = .melee(.primitive, .range(13, 27)),
}),

rusty_sword: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .rusty_sword },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 32 },
    .weapon = .melee(.primitive, .range(2, 6)),
}),

saber: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .saber },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 66 },
    .weapon = .melee(.tricky, .range(3, 7)),
}),

short_bow: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .short_bow },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 68 },
    .weapon = .ranged(.tricky, .range(1, 5), 3, .arrows),
}),

short_sword: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .short_sword },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 62 },
    .weapon = .melee(.primitive, .range(4, 8)),
}),

signal_pistol: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 6 },
    .description = .{ .preset = .signal_pistol },
    .sprite = .{ .codepoint = cp.weapon_ranged },
    .price = .{ .value = 760 },
    .weapon = .rangedWithEffect(.ancient, .range(13, 25), 4, .bullets, .fire),
}),

spiked_club: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 2 },
    .description = .{ .preset = .spiked_club },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 70 },
    .weapon = .melee(.primitive, .range(3, 9)),
}),

steam_cutter: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 8 },
    .description = .{ .preset = .steam_cutter },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 1120 },
    .weapon = .melee(.ancient, .range(34, 102)),
}),

stiletto: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .stiletto },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 28 },
    .weapon = .melee(.tricky, .range(1, 5)),
}),

tesla_rod: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 8 },
    .description = .{ .preset = .tesla_rod },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 1380 },
    .weapon = .meleeWithEffect(.ancient, .range(50, 100), .fire),
}),

torch: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 1 },
    .description = .{ .preset = .torch },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 14 },
    .weapon = .meleeWithEffect(.primitive, .range(1, 3), .fire),
}),

war_hammer: c.Components = archetype.weapon(.{
    .tier = .{ .tier = 7 },
    .description = .{ .preset = .war_hammer },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .price = .{ .value = 920 },
    .weapon = .melee(.primitive, .range(31, 61)),
}),
