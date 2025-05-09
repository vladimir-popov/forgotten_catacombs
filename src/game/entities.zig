const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub fn player(alloc: std.mem.Allocator) c.Components {
    return .{
        .sprite = .{ .codepoint = cp.human, .z_order = 3 },
        .description = .{ .name = "You" },
        .health = .{ .max = 100, .current = 100 },
        .speed = .{ .move_points = 10 },
        .equipment = .nothing,
        .inventory = c.Inventory.empty(alloc),
    };
}

pub const Rat = c.Components{
    .initiative = .empty,
    .sprite = .{ .codepoint = 'r', .z_order = 3 },
    .description = .{ .name = "Rat" },
    .health = .{ .max = 10, .current = 10 },
    .weapon = .{ .min_damage = 1, .max_damage = 3 },
    .speed = .{ .move_points = 14 },
    .state = .sleeping,
};

pub const Club = c.Components{
    .description = .{ .name = "Club" },
    .weapon = .{ .min_damage = 2, .max_damage = 5 },
};

pub const Torch = c.Components{
    .description = .{ .name = "Torch", .description =&.{
        "This is regular",
        "torch",
    } },
    .source_of_light = .{ .radius = 5 },
};

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

pub fn ladder(l: c.Ladder) c.Components {
    return switch (l.direction) {
        .up => .{
            .ladder = l,
            .description = .{ .name = "Ladder up" },
            .sprite = .{ .codepoint = cp.ladder_up, .z_order = 2 },
        },
        .down => .{
            .ladder = l,
            .description = .{ .name = "Ladder down" },
            .sprite = .{ .codepoint = cp.ladder_down, .z_order = 2 },
        },
    };
}

pub fn teleport(place: p.Point) c.Components {
    return .{
        .position = .{ .point = place },
        .sprite = .{ .codepoint = cp.teleport, .z_order = 1 },
        .description = .{ .name = "Teleport" },
    };
}
