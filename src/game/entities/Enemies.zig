const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

rat: c.Components = archetype.enemy(.{
    .armor = .init(&.{.physical(0, 1)}),
    .description = .{ .preset = .rat },
    .experience = .reward(10),
    .stats = .zeros,
    .skills = .zeros,
    .initiative = .empty,
    .sprite = .{ .codepoint = 'r' },
    .health = .{ .max = 10, .current = 10 },
    .effects = .init(&.{.physical(1, 3)}),
    .regeneration = .regular,
    .speed = .{ .move_points = 14 },
    .state = .sleeping,
}),

snake: c.Components = archetype.enemy(.{
    .armor = .init(&.{}),
    .description = .{ .preset = .snake },
    .experience = .reward(20),
    .stats = .init(0, 1, 0, 0, 0),
    .skills = .zeros,
    .initiative = .empty,
    .sprite = .{ .codepoint = 's' },
    .health = .init(8),
    .effects = .init(&.{.poisoning(1, 3)}),
    .regeneration = .regular,
    .speed = .{ .move_points = 9 },
    .state = .sleeping,
}),

/// Gets a Components from the preset `item`, adds a Position component with the `place`,
/// and returns completed structure.
pub fn atPlace(item: anytype, place: p.Point) c.Components {
    var enemy = g.presets.Enemies.get(item);
    enemy.position = .{ .place = place, .zorder = .obstacle };
    return enemy;
}
