const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
pub const items = @import("items.zig");

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

const Rat = archetype.enemy(.{
    .armor = .init(.{ .physical = 1 }),
    .description = .{ .preset = .rat },
    .initiative = .empty,
    .sprite = .{ .codepoint = 'r' },
    .health = .{ .max = 10, .current = 10 },
    .damage = .{ .damage_type = .physical, .min = 1, .max = 3 },
    .reward = .{ .experience = 5 },
    .speed = .{ .move_points = 14 },
    .state = .sleeping,
});

pub fn rat(place: p.Point) c.Components {
    var entity = Rat;
    entity.position = .{ .zorder = .obstacle, .place = place };
    return entity;
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
    try fillShop(&shop, registry, seed);
    return .{
        .position = .{ .place = place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
        .shop = shop,
    };
}

pub fn fillShop(shop: *c.Shop, registry: *g.Registry, seed: u64) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const count = rand.uintAtMost(usize, 5) + 10;
    var proportions: [g.presets.Items.values.values.len]u8 = undefined;
    var i: usize = 0;
    var itr = g.presets.Items.iterator();
    while (itr.next()) |item| {
        proportions[i] = @intFromEnum(item.rarity.?);
        i += 1;
    }
    for (0..count) |_| {
        const item = g.presets.Items.values.values[rand.weightedIndex(u8, &proportions)];
        try shop.items.add(try registry.addNewEntity(item.*));
    }
}
