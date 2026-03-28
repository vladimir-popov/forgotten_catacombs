//! Contains method to generate random entities
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const GeneratingTarget = union(enum) {
    shop,
    dungeon,
    reward: struct { enemy_level: u8 },
};

/// Chooses a random enemy from the preset according to the specified depth,
/// and adds that enemy to the registry as a new entity.
/// Return the id of the generated enemy.
pub fn generateEnemy(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    _ = depth;
    const idx = rand.uintLessThan(usize, g.entities.presets.Enemies.fields.values.len);
    var enemy = g.entities.presets.Enemies.fields.values[idx].*;
    enemy.state = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
    return try registry.addNewEntity(enemy);
}

pub fn generateTrap(registry: *g.Registry, rand: std.Random, place: p.Point) !g.Entity {
    return try registry.addNewEntity(
        g.entities.trap(place, rand.int(u3), c.Effects.chooseRandomType(rand)),
    );
}

/// Generates optional reward for killing an enemy.
pub fn generateReward(
    registry: *g.Registry,
    rand: std.Random,
    target: GeneratingTarget,
    depth: u8,
    player_level: u8,
) !?g.Entity {
    if (rand.uintLessThan(u8, 10) < 4) return null;

    var proportions: [g.entities.presets.Items.fields.values.len]u8 = undefined;
    itemsChanceProportions(&proportions, depth, target, player_level);
    return try generateItem(registry, rand, &proportions);
}

/// Chooses a random item from the preset using the weighted index and adds that item
/// as a new entity to the registry. If the item is a weapon or an armor, this method adds a random
/// modification with 20% chance.
/// Returns the id of the generated item.
pub fn generateItem(registry: *g.Registry, rand: std.Random, proportions: []const u8) !g.Entity {
    const idx = rand.weightedIndex(u8, proportions);
    const item = g.entities.presets.Items.fields.values[idx];
    const entity = try registry.addNewEntity(item.*);
    // Randomly modify a weapon:
    if (registry.get(entity, c.Weapon)) |weapon| {
        if (rand.uintAtMost(u8, 100) < 15) {
            const codepoint: g.Codepoint = if (weapon.ammunition_type) |_|
                g.codepoints.weapon_ranged_unknown
            else
                g.codepoints.weapon_melee_unknown;
            try g.meta.modifyEntity(registry, rand, entity, codepoint, -5, 5, null);
        }
    }
    // Randomly modify an armor:
    else if (registry.has(entity, c.Protection)) {
        if (rand.uintAtMost(u8, 100) < 15) {
            try g.meta.modifyEntity(registry, rand, entity, g.codepoints.armor_unknown, -5, 5, null);
        }
    }
    return entity;
}

/// Builds a weighted index for all items.
pub fn itemsChanceProportions(
    proportions: *[g.entities.presets.Items.fields.values.len]u8,
    depth: u8,
    target: GeneratingTarget,
    player_level: u8,
) void {
    var i: usize = 0;
    var itr = g.entities.presets.Items.iterator();
    while (itr.next()) |item| {
        proportions[i] = itemChanceProportion(item.rarity.?, item.tier.?, depth, target, player_level);
        i += 1;
    }
}

/// Returns a chance for the item to appear at the target (shop, dungeon, or as a reward).
fn itemChanceProportion(rarity: c.Rarity, tier: c.Tier, depth: u8, target: GeneratingTarget, player_level: u8) u8 {
    const actual_tier: i8 = @intCast(switch (target) {
        // The actual tier depends on the player level and the target's depth.
        // No high level items too earlier or  for low level player
        .shop, .dungeon => @max(player_level / 5, depth / 15) + 1,

        // The actual tier depends on the player level and the level of the killed enemy.
        // A high level items for high level player or as a reward for killing a high level enemy
        .reward => |reward| @max(player_level / 5, reward.enemy_level / 5) + 1,
    });

    const tier_difference: i8 = if (tier.value == 0) 0 else actual_tier - tier.value;

    // Do not generate too weak or too powerful items:
    if (tier_difference > 1) return 0;
    if (tier_difference < -1) return 0;

    const tier_difference_penalty: f32 = switch (tier_difference) {
        // the player level is to low for the item's tier.
        // the chance for the item should be decreased
        -1 => 0.5,
        // the player level is to high for the item's tier
        // the chance for the item should be increased
        1 => 2.0,
        // otherwise the chance should not be changed
        else => 1.0,
    };

    const proportion: f32 = @floatFromInt(@intFromEnum(rarity));
    return @intFromFloat(@round(proportion * tier_difference_penalty));
}

/// Algorithm of filling a shop:
/// 1. Build a weighted index for all defined in `g.entities.Items` items according to their tier;
/// 2. Randomly choose a count of items in the shop: [10, 15]
/// 3. Randomly getting items
pub fn fillShop(registry: *g.Registry, shop: *c.Shop, depth: u8, player_level: u8) !void {
    var prng = std.Random.DefaultPrng.init(shop.seed);
    const rand = prng.random();
    const count = rand.uintAtMost(usize, 5) + 10;
    var proportions: [g.entities.presets.Items.fields.values.len]u8 = undefined;
    itemsChanceProportions(&proportions, depth, .shop, player_level);
    for (0..count) |_| {
        const entity = try generateItem(registry, rand, &proportions);
        try shop.items.add(entity);
    }
}
