const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub fn player(alloc: std.mem.Allocator) !c.Components {
    return .{
        .sprite = .{ .codepoint = cp.human },
        .z_order = .{ .order = .obstacle },
        .description = .{ .ptr = &g.Description.player },
        .health = .{ .max = 30, .current = 30 },
        .speed = .{ .move_points = 10 },
        .equipment = .nothing,
        .inventory = c.Inventory.empty(alloc),
    };
}

pub const Rat = c.Components{
    .initiative = .empty,
    .sprite = .{ .codepoint = 'r' },
    .z_order = .{ .order = .obstacle },
    .description = .{ .ptr = &g.Description.rat },
    .health = .{ .max = 10, .current = 10 },
    .weapon = .{ .min_damage = 1, .max_damage = 3 },
    .speed = .{ .move_points = 14 },
    .state = .sleeping,
};

pub const Club = c.Components{
    .description = .{ .ptr = &g.Description.club },
    .z_order = .{ .order = .item },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weapon = .{ .min_damage = 2, .max_damage = 5 },
};

pub const Torch = c.Components{
    .description = .{ .ptr = &g.Description.torch },
    .z_order = .{ .order = .item },
    .sprite = .{ .codepoint = cp.source_of_light },
    .source_of_light = .{ .radius = 5 },
};

pub const OpenedDoor = c.Components{
    .door = .{ .state = .opened },
    .z_order = .{ .order = .floor },
    .sprite = .{ .codepoint = cp.door_opened },
    .description = .{ .ptr = &g.Description.opened_door },
};

pub const ClosedDoor = c.Components{
    .door = .{ .state = .closed },
    .z_order = .{ .order = .obstacle },
    .sprite = .{ .codepoint = cp.door_closed },
    .description = .{ .ptr = &g.Description.closed_door },
};

pub fn ladder(l: c.Ladder) c.Components {
    return switch (l.direction) {
        .up => .{
            .ladder = l,
            .description = .{ .ptr = &g.Description.ladder_up },
            .z_order = .{ .order = .floor },
            .sprite = .{ .codepoint = cp.ladder_up },
        },
        .down => .{
            .ladder = l,
            .description = .{ .ptr = &g.Description.ladder_down },
            .z_order = .{ .order = .floor },
            .sprite = .{ .codepoint = cp.ladder_down },
        },
    };
}

pub fn teleport(place: p.Point) c.Components {
    return .{
        .position = .{ .place = place },
        .z_order = .{ .order = .floor },
        .sprite = .{ .codepoint = cp.teleport },
        .description = .{ .ptr = &g.Description.teleport },
    };
}

pub fn pile(alloc: std.mem.Allocator) !c.Components {
    return .{
        .z_order = .{ .order = .item },
        .sprite = .{ .codepoint = cp.pile },
        .description = .{ .ptr = &g.Description.pile },
        .pile = c.Pile.empty(alloc),
    };
}
