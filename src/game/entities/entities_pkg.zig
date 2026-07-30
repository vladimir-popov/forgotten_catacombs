const std = @import("std");
const archetype = @import("archetypes.zig");
const cp = @import("../codepoints.zig");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const entities = @This();

const ammo = @import("ammo.zig");
const armor = @import("armor.zig");
const enemies = @import("enemies.zig");
const food = @import("food.zig");
const items = @import("items.zig");
const potions = @import("potions.zig");
const weapons = @import("weapons.zig");

pub const generators = @import("generators.zig");

pub const presets = struct {
    pub const Ammo = g.utils.Preset(g.components.Components, entities.ammo);
    pub const Armor = g.utils.Preset(g.components.Components, entities.armor);
    pub const Enemies = g.utils.Preset(g.components.Components, entities.enemies);
    pub const Food = g.utils.Preset(g.components.Components, entities.food);
    pub const Items = g.utils.Preset(g.components.Components, entities.items);
    pub const Potions = g.utils.Preset(g.components.Components, entities.potions);
    pub const Weapons = g.utils.Preset(g.components.Components, entities.weapons);
};

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
        .speed = .default,
        .sprite = .{ .codepoint = cp.human },
        .stats = stats,
        .wallet = .{ .money = rand.uintAtMost(u16, 50) + 100 },
        .weapon = .melee(.tricky, .range(1, 3)),
    };
}

/// Gets a Components from the preset `item`, adds a Position component with the `place`,
/// and returns completed structure.
pub fn enemyAtPlace(item: anytype, place: p.Point) c.Components {
    var enemy = g.entities.presets.Enemies.get(item);
    enemy.position = .{ .place = place, .zorder = .obstacle };
    return enemy;
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

pub fn goldPile(value: u16) c.Components {
    return .{
        .description = .{ .preset = .gold_pile },
        .sprite = .{ .codepoint = cp.gold },
        .price = .{ .value = value },
        .wallet = .{ .money = value },
    };
}

pub fn scientist(place: p.Point) c.Components {
    return .{
        .position = .{ .place = place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .scientist },
    };
}

pub fn trader(
    registry: *g.Registry,
    place: p.Point,
    balance: u16,
) !c.Components {
    return .{
        .position = .{ .place = place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
        .shop = try c.Shop.empty(registry.allocator()),
        .wallet = .{ .money = balance },
    };
}

pub fn trap(place: p.Point, power: u2) c.Components {
    return .{
        .description = .{ .preset = .trap },
        .sprite = .{ .codepoint = cp.trap },
        .trap = .{ .power = power },
        .position = .{ .place = place, .zorder = .item },
    };
}
