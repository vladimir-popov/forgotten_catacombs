const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
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

pub const Torch = archetype.weapon(.{
    .description = .{ .preset = .torch },
    .sprite = .{ .codepoint = cp.source_of_light },
    .weight = .{ .value = 20 },
    .source_of_light = .{ .radius = 5 },
    .price = .{ .value = 5 },
    .damage = .{ .damage_type = .blunt, .min = 2, .max = 3 },
    .effect = .{ .effect_type = .burning, .min = 1, .max = 1 },
});

pub const Pickaxe = archetype.weapon(.{
    .description = .{ .preset = .pickaxe },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 100 },
    .damage = .{ .damage_type = .cutting, .min = 3, .max = 5 },
    .price = .{ .value = 15 },
});

pub const Club = archetype.weapon(.{
    .description = .{ .preset = .club },
    .sprite = .{ .codepoint = cp.weapon_melee },
    .weight = .{ .value = 80 },
    .damage = .{ .damage_type = .blunt, .min = 5, .max = 8 },
    .price = .{ .value = 28 },
});

// The first effect describes the type of the potion
pub const HealingPotion = archetype.potion(.{
    .description = .{ .preset = .healing_potion },
    .sprite = .{ .codepoint = cp.potion },
    .effect = .{ .effect_type = .healing, .min = 20, .max = 25 },
    .weight = .{ .value = 10 },
    .price = .{ .value = 20 },
    .consumable = .{ .consumable_type = .potion, .calories = 10 },
});

pub fn rat(place: p.Point) c.Components {
    return archetype.enemy(.{
        .description = .{ .preset = .rat },
        .initiative = .empty,
        .sprite = .{ .codepoint = 'r' },
        .position = .{ .zorder = .obstacle, .place = place },
        .health = .{ .max = 10, .current = 10 },
        .damage = .{ .damage_type = .thrusting, .min = 1, .max = 3 },
        .speed = .{ .move_points = 14 },
        .state = .sleeping,
    });
}

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
