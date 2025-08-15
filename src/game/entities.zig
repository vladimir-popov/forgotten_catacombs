const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

/// Creates components for the player with empty inventory and nothing equipped.
///
/// - `alloc` the ecs.Registry allocator.
pub fn player(alloc: std.mem.Allocator) !c.Components {
    return .{
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .player },
        .health = .{ .max = 30, .current = 30 },
        .speed = .{ .move_points = 10 },
        .equipment = .nothing,
        .inventory = try c.Inventory.empty(alloc),
        .wallet = .{ .money = 0 },
    };
}

pub fn rat(place: p.Point) c.Components {
    return .{
        .initiative = .empty,
        .sprite = .{ .codepoint = 'r' },
        .position = .{ .zorder = .obstacle, .place = place },
        .description = .{ .preset = .rat },
        .health = .{ .max = 10, .current = 10 },
        .weapon = c.Weapon.thrusting(1, 3),
        .speed = .{ .move_points = 14 },
        .state = .sleeping,
    };
}

pub const Torch = c.Components{
    .description = .{ .preset = .torch },
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 20 },
    .source_of_light = .{ .radius = 5 },
    .price = .{ .value = 5 },
    .weapon = c.Weapon.withEffect(.blunt, 2, 3, .{ .burning = .{ .power = 2, .decrease = 1 } }),
};

pub const Pickaxe = c.Components{
    .description = .{ .preset = .pickaxe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 100 },
    .weapon = c.Weapon.cutting(3, 5),
    .price = .{ .value = 15 },
};

pub const Club = c.Components{
    .description = .{ .preset = .club },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 80 },
    .weapon = c.Weapon.blunt(5, 8),
    .price = .{ .value = 28 },
};

// The first effect describes the type of the potion
pub const HealingPotion = c.Components{
    .description = .{ .preset = .healing_potion },
    .sprite = .{ .codepoint = cp.potion },
    .potion = .{ .effect = .{ .healing = .{ .power = 20, .decrease = 20 } } },
    .weight = .{ .value = 10 },
    .price = .{ .value = 20 },
};

pub fn openedDoor(place: p.Point) c.Components {
    return .{
        .door = .{ .state = .opened },
        .position = .{ .zorder = .floor, .place = place },
        .sprite = .{ .codepoint = cp.door_opened },
        .description = .{ .preset = .opened_door },
    };
}

pub fn closedDoor(place: p.Point) c.Components {
    return .{
        .door = .{ .state = .closed },
        .position = .{ .zorder = .obstacle, .place = place },
        .sprite = .{ .codepoint = cp.door_closed },
        .description = .{ .preset = .closed_door },
    };
}

pub fn ladder(l: c.Ladder, place: p.Point) c.Components {
    return switch (l.direction) {
        .up => .{
            .ladder = l,
            .description = .{ .preset = .ladder_up },
            .position = .{ .zorder = .floor, .place = place },
            .sprite = .{ .codepoint = cp.ladder_up },
        },
        .down => .{
            .ladder = l,
            .description = .{ .preset = .ladder_down },
            .position = .{ .zorder = .floor, .place = place },
            .sprite = .{ .codepoint = cp.ladder_down },
        },
    };
}

pub fn teleport(place: p.Point) c.Components {
    return .{
        .position = .{ .place = place, .zorder = .floor },
        .sprite = .{ .codepoint = cp.teleport },
        .description = .{ .preset = .teleport },
    };
}

pub fn pile(alloc: std.mem.Allocator, place: p.Point) !c.Components {
    return .{
        .position = .{ .zorder = .item, .place = place },
        .sprite = .{ .codepoint = cp.pile },
        .description = .{ .preset = .pile },
        .pile = try c.Pile.empty(alloc),
    };
}
