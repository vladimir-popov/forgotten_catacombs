const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

rat: c.Components = archetype.enemy(.{
    .description = .{ .preset = .rat },
    .experience = .reward(10),
    .health = .{ .max = 10, .current_hp = 10 },
    .initiative = .empty,
    .protection = .init(.{ .physical = .range(0, 1) }),
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .{ .move_points = 14 },
    .sprite = .{ .codepoint = 'r' },
    .state = .sleeping,
    .stats = .zeros,
    .weapon = .melee(.primitive, .effects(.{ .physical = .range(1, 3) })),
}),

snake: c.Components = archetype.enemy(.{
    .protection = .zeros,
    .description = .{ .preset = .snake },
    .experience = .reward(20),
    .stats = .init(0, 1, 0, 0, 0),
    .skills = .zeros,
    .initiative = .empty,
    .sprite = .{ .codepoint = 's' },
    .health = .init(8),
    .regeneration = .regular,
    .speed = .{ .move_points = 9 },
    .state = .sleeping,
    .weapon = .melee(.tricky, .effects(.{ .poison = .range(1, 3) })),
}),
