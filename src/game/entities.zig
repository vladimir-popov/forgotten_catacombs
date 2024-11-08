const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Player = c.Components{
    .sprite = .{ .codepoint = '@', .z_order = 3 },
    .description = .{ .name = "You" },
    .health = .{ .max = 100, .current = 30 },
    .melee_weapon = .{ .max_damage = 3, .move_points = 5 },
    .speed = .{ .move_points = 10 },
};

pub fn Entrance(this_ladder: g.Entity, that_ladder: ?g.Entity) c.Components {
    return .{
        .ladder = .{ .this_ladder = this_ladder, .that_ladder = that_ladder, .direction = .up },
        .description = .{ .name = "Ladder up" },
        .sprite = .{ .codepoint = '<', .z_order = 2 },
    };
}

pub fn Exit(this_ladder: g.Entity, that_ladder: ?g.Entity) c.Components {
    return .{
        .ladder = .{ .this_ladder = this_ladder, .that_ladder = that_ladder, .direction = .down },
        .description = .{ .name = "Ladder down" },
        .sprite = .{ .codepoint = '>', .z_order = 2 },
    };
}

pub const OpenedDoor = c.Components{
    .door = .{ .state = .opened },
    .sprite = .{ .codepoint = '\'' },
    .description = .{ .name = "Opened door" },
};

pub const ClosedDoor = c.Components{
    .door = .{ .state = .closed },
    .sprite = .{ .codepoint = '+' },
    .description = .{ .name = "Closed door" },
};

pub const Rat = c.Components{
    .npc = .{ .type = .melee },
    .sprite = .{ .codepoint = 'r', .z_order = 3 },
    .description = .{ .name = "Rat" },
    .health = .{ .max = 10, .current = 10 },
    .melee_weapon = .{ .max_damage = 3, .move_points = 10 },
    .speed = .{ .move_points = 10 },
};
