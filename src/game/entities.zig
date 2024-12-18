const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Player = c.Components{
    .sprite = .{ .codepoint = cp.player, .z_order = 3 },
    .description = .{ .name = "You" },
    .health = .{ .max = 100, .current = 50 },
    .weapon = .{ .max_damage = 3, .move_scale = 0.5 },
    .speed = .{ .move_speed = 10 },
};

pub fn Ladder(ladder: c.Ladder) c.Components {
    return switch (ladder.direction) {
        .up => .{
            .ladder = ladder,
            .description = .{ .name = "Ladder up" },
            .sprite = .{ .codepoint = cp.ladder_up, .z_order = 2 },
        },
        .down => .{
            .ladder = ladder,
            .description = .{ .name = "Ladder down" },
            .sprite = .{ .codepoint = cp.ladder_down, .z_order = 2 },
        },
    };
}

pub const OpenedDoor = c.Components{
    .door = .{ .state = .opened },
    .sprite = .{ .codepoint = cp.door_opened, .z_order = 0 },
    .description = .{ .name = "Opened door" },
};

pub const ClosedDoor = c.Components{
    .door = .{ .state = .closed },
    .sprite = .{ .codepoint = cp.door_closed, .z_order = 0 },
    .description = .{ .name = "Closed door" },
};

pub const Rat = c.Components{
    .initiative = .{},
    .sprite = .{ .codepoint = 'r', .z_order = 3 },
    .description = .{ .name = "Rat" },
    .health = .{ .max = 10, .current = 10 },
    .weapon = .{ .max_damage = 3 },
    .speed = .{ .move_speed = 10 },
};
