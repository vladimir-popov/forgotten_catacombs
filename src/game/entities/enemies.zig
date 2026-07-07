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
    .regeneration = .regular,
    .skills = .zeros,
    .speed = .default,
    .sprite = .{ .codepoint = 'r' },
    .state = .sleeping,
    .stats = .zeros,
    .weapon = .melee(.primitive, .range(3, 8)),
}),

snake: c.Components = archetype.enemy(.{
    .description = .{ .preset = .snake },
    .experience = .reward(20),
    .stats = .init(0, 1, 0, 0, 0),
    .skills = .zeros,
    .initiative = .empty,
    .sprite = .{ .codepoint = 's' },
    .health = .init(8),
    .regeneration = .regular,
    .speed = .default,
    .state = .sleeping,
    .weapon = .melee(.tricky, .range(5, 7)),
}),
