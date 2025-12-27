const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Items = @import("Items.zig");
pub const Enemies = @import("Enemies.zig");

/// Creates components for the player with empty inventory and nothing equipped.
///
/// - `alloc` the ecs.Registry allocator.
pub fn player(
    alloc: std.mem.Allocator,
    rand: std.Random,
    stats: c.Stats,
    skills: c.Skills,
    health: c.Health,
) !c.Components {
    return .{
        .description = .{ .preset = .player },
        .equipment = .nothing,
        .experience = .zero,
        .health = health,
        .hunger = .well_fed,
        .inventory = try c.Inventory.empty(alloc),
        .regeneration = .regular,
        .skills = skills,
        .speed = .{ .move_points = g.MOVE_POINTS_IN_TURN },
        .sprite = .{ .codepoint = cp.human },
        .stats = stats,
        .wallet = .{ .money = rand.uintAtMost(u16, 20) + 30 },
    };
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

pub fn trader(
    registry: *g.Registry,
    place: p.Point,
    price_multiplier: f16,
    balance: u16,
    seed: u64,
) !c.Components {
    var shop = try c.Shop.empty(registry.allocator(), price_multiplier, balance);
    try g.meta.fillShop(&shop, registry, seed);
    return .{
        .position = .{ .place = place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
        .shop = shop,
    };
}
