const archetype = @import("archetypes.zig");
const g = @import("../game_pkg.zig");
const c = g.components;

// Trait mapping reference (unique values from this CSV):
//   ACID -> weapon effect via meleeWithEffect/rangedWithEffect(..., .poison/.fire/.acid)
//   ARM -> armor.protection uses the numeric Armor column
//   ATK+ -> speed = .@"atk+"
//   ATK- -> speed = .@"atk-" (or .@"spd-; atk-" with SPD-)
//   DEX+ -> stats = .init(dexterity 1, ...)
//   DEX- -> stats = .init(dexterity -1, ...)
//   F+ -> .improvements = .{ .modifications = .init(&.{ .fire }) }
//   F- -> breakages = .@"fire-"
//   FIRE -> weapon effect via meleeWithEffect/rangedWithEffect(..., .poison/.fire/.acid)
//   P+ -> .improvements = .{ .modifications = .init(&.{ .poison }) }
//   PER+ -> stats = .init(perception 1, ...)
//   POISON -> weapon effect via meleeWithEffect/rangedWithEffect(..., .poison/.fire/.acid)
//   RNG(4) -> weapon = .ranged(..., max_distance, .bullets)
//   RNG(5) -> weapon = .ranged(..., max_distance, .bullets)
//   SPD+ -> speed = .@"spd+"
//   SPD- -> speed = .@"spd-" (or .@"spd-; atk-" with ATK-)
//   STATIC -> speed = .@"static; atk+" when combined with ATK+

cave_snake: c.Components = archetype.enemy(.{
    .description = .{ .preset = .cave_snake },
    .tier = .{ .tier = 1 },
    .experience = .reward(2),
    .health = .init(11),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 's' },
    .state = .sleeping,
    .stats = .init(0, 1, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(1, 2), .poison),
}),

cave_rat: c.Components = archetype.enemy(.{
    .description = .{ .preset = .cave_rat },
    .tier = .{ .tier = 1 },
    .experience = .reward(3),
    .health = .init(12),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'r' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(1, 2)),
}),

bat: c.Components = archetype.enemy(.{
    .description = .{ .preset = .bat },
    .tier = .{ .tier = 1 },
    .experience = .reward(2),
    .health = .init(10),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .@"spd+; atk+",
    .sprite = .{ .codepoint = 'b' },
    .state = .sleeping,
    .stats = .init(0, 1, 0, 0, 0),
    .weapon = .melee(.native, .range(1, 2)),
}),

cave_hound: c.Components = archetype.enemy(.{
    .description = .{ .preset = .cave_hound },
    .tier = .{ .tier = 2 },
    .experience = .reward(6),
    .health = .init(16),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'h' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(2, 4)),
}),

worm: c.Components = archetype.enemy(.{
    .description = .{ .preset = .worm },
    .tier = .{ .tier = 2 },
    .experience = .reward(8),
    .health = .init(17),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(1, 1),
    },
    .speed = .default,
    .sprite = .{ .codepoint = 'w' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(2, 4)),
}),

carrion_feeder: c.Components = archetype.enemy(.{
    .description = .{ .preset = .carrion_feeder },
    .tier = .{ .tier = 3 },
    .experience = .reward(10),
    .health = .init(27),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'f' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(3, 5)),
}),

armadillo_beast: c.Components = archetype.enemy(.{
    .description = .{ .preset = .armadillo_beast },
    .tier = .{ .tier = 4 },
    .experience = .reward(13),
    .health = .init(40),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(3, 3),
    },
    .speed = .@"spd-",
    .sprite = .{ .codepoint = 'p' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(4, 6)),
}),

venom_centipede: c.Components = archetype.enemy(.{
    .description = .{ .preset = .venom_centipede },
    .tier = .{ .tier = 3 },
    .experience = .reward(10),
    .health = .init(27),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'c' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(3, 5), .poison),
}),

acid_centipede: c.Components = archetype.enemy(.{
    .description = .{ .preset = .acid_centipede },
    .tier = .{ .tier = 3 },
    .experience = .reward(10),
    .health = .init(27),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'c' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(3, 5), .acid),
}),

fire_centipede: c.Components = archetype.enemy(.{
    .description = .{ .preset = .fire_centipede },
    .tier = .{ .tier = 4 },
    .experience = .reward(18),
    .health = .init(41),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'c' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(4, 6), .fire),
}),

giant_venom_ant: c.Components = archetype.enemy(.{
    .description = .{ .preset = .giant_venom_ant },
    .tier = .{ .tier = 4 },
    .experience = .reward(13),
    .health = .init(36),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'a' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(4, 6), .poison),
}),

giant_acid_ant: c.Components = archetype.enemy(.{
    .description = .{ .preset = .giant_acid_ant },
    .tier = .{ .tier = 4 },
    .experience = .reward(15),
    .health = .init(36),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'a' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(4, 6), .acid),
}),

giant_fire_ant: c.Components = archetype.enemy(.{
    .description = .{ .preset = .giant_fire_ant },
    .tier = .{ .tier = 4 },
    .experience = .reward(18),
    .health = .init(36),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'a' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(4, 6), .fire),
}),

cave_spider: c.Components = archetype.enemy(.{
    .description = .{ .preset = .cave_spider },
    .tier = .{ .tier = 5 },
    .experience = .reward(22),
    .health = .init(67),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(4, 4),
    },
    .speed = .@"spd-; atk-",
    .sprite = .{ .codepoint = 'm' },
    .state = .sleeping,
    .stats = .init(0, -1, 1, 0, 0),
    .weapon = .ranged(.native, .range(5, 7), 4, .bullets),
}),

repair_drone: c.Components = archetype.enemy(.{
    .description = .{ .preset = .repair_drone },
    .tier = .{ .tier = 5 },
    .experience = .reward(20),
    .health = .init(49),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(4, 4),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'd' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(6, 8)),
}),

mechatron: c.Components = archetype.enemy(.{
    .description = .{ .preset = .mechatron },
    .tier = .{ .tier = 5 },
    .experience = .reward(24),
    .health = .init(67),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(4, 4),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .@"spd-",
    .sprite = .{ .codepoint = 'M' },
    .state = .sleeping,
    .stats = .init(0, -1, 0, 0, 0),
    .weapon = .melee(.native, .range(6, 8)),
}),

turret: c.Components = archetype.enemy(.{
    .description = .{ .preset = .turret },
    .tier = .{ .tier = 6 },
    .experience = .reward(26),
    .health = .init(82),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(6, 6),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .@"static; atk+",
    .sprite = .{ .codepoint = 't' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .ranged(.native, .range(5, 7), 5, .bullets),
}),

robot: c.Components = archetype.enemy(.{
    .description = .{ .preset = .robot },
    .tier = .{ .tier = 6 },
    .experience = .reward(28),
    .health = .init(82),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(6, 6),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .default,
    .sprite = .{ .codepoint = 'R' },
    .state = .sleeping,
    .stats = .init(0, 0, 0, 0, 0),
    .weapon = .melee(.native, .range(6, 10)),
}),

cyborg: c.Components = archetype.enemy(.{
    .description = .{ .preset = .cyborg },
    .tier = .{ .tier = 7 },
    .experience = .reward(47),
    .health = .init(98),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(9, 9),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'C' },
    .state = .sleeping,
    .stats = .init(0, 1, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(7, 11), .fire),
}),

terminator: c.Components = archetype.enemy(.{
    .description = .{ .preset = .terminator },
    .tier = .{ .tier = 8 },
    .experience = .reward(70),
    .health = .init(146),
    .initiative = .empty,
    .regeneration = .regular,
    .skills = .zeros,
    .armor = .{
        .protection = .range(14, 14),
    },
    .improvements = .{ .modifications = .init(&.{ .fire, .poison }) },
    .speed = .@"spd+",
    .sprite = .{ .codepoint = 'T' },
    .state = .sleeping,
    .stats = .init(0, 1, 0, 0, 0),
    .weapon = .meleeWithEffect(.native, .range(10, 14), .fire),
}),
