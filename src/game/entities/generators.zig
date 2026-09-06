//! Contains methods to generate random entities
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

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
    return try registry.addNewEntity(g.entities.trap(place, rand.int(u2)));
}

pub fn generateItem(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    return generateRandomItem(registry, rand, depth, &general_proportions.values);
}

pub fn generateReward(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    return generateRandomItem(registry, rand, depth, &general_proportions.values);
}

pub fn fillShop(registry: *g.Registry, rand: std.Random, shop: *c.Shop, depth: u8) !void {
    const count = rand.uintAtMost(usize, 5) + 10;
    var proportions = general_proportions.values;
    // we don't need gold here
    proportions[0] = 0;
    for (0..count) |_| {
        const entity = try generateRandomItem(registry, rand, depth, &proportions);
        try shop.items.add(entity);
    }
}

// The type of items to generate:
const GeneratedItems = enum {
    gold,
    weapon,
    improved_weapon,
    broken_weapon,
    armor,
    improved_armor,
    broken_armor,
    food,
    potions,
    ammo,
    torch,
    // oil has more chance to be generate than any other potion
    oil,
};

const general_proportions: std.enums.EnumMap(GeneratedItems, u8) = .init(.{
    .gold = 28,
    .weapon = 14,
    .improved_weapon = 6,
    .broken_weapon = 8,
    .armor = 12,
    .improved_armor = 4,
    .broken_armor = 8,
    .food = 12,
    .potions = 8,
    .ammo = 10,
    .torch = 10,
    // oil has more chance to be generate than any other potion
    .oil = 6,
});

/// Chooses a random item from the presets using the proportions of the weight index and adds that item
/// as a new entity to the registry.
///
/// Returns the id of the generated item.
fn generateRandomItem(registry: *g.Registry, rand: std.Random, depth: u8, proportions: []const u8) !g.Entity {
    const item_type: GeneratedItems =
        @enumFromInt(rand.weightedIndex(u8, proportions));

    switch (item_type) {
        .gold => return try generateGoldPile(registry, rand, depth),
        .weapon => return try generateWeapon(registry, rand, depth),
        .improved_weapon => {
            const entity = try generateWeapon(registry, rand, depth);
            _ = try g.meta.improveItem(registry, rand, entity, null);
            return entity;
        },
        .broken_weapon => {
            const entity = try generateWeapon(registry, rand, depth);
            _ = try g.meta.breakItem(registry, rand, entity, null);
            return entity;
        },
        .armor => return try generateArmor(registry, rand, depth),
        .improved_armor => {
            const entity = try generateArmor(registry, rand, depth);
            _ = try g.meta.improveItem(registry, rand, entity, null);
            return entity;
        },
        .broken_armor => {
            const entity = try generateArmor(registry, rand, depth);
            _ = try g.meta.breakItem(registry, rand, entity, null);
            return entity;
        },
        .food => return try generateFood(registry, rand),
        .potions => return try generatePotion(registry, rand),
        .ammo => return try generateAmmo(registry, rand),
        .torch => return try registry.addNewEntity(g.entities.presets.Items.get(.torch)),
        .oil => return try registry.addNewEntity(g.entities.presets.Potions.get(.oil_potion)),
    }
}

/// Min and max size of the gold piles depending on the depth
const gold_piles = [_]p.Range(u16){
    .range(0, 0),
    .range(6, 15),
    .range(14, 36),
    .range(24, 64),
    .range(36, 94),
    .range(48, 128),
    .range(62, 162),
    .range(76, 200),
    .range(91, 239),
    .range(107, 281),
};

fn generateGoldPile(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    const gold_pile = gold_piles[depth];
    const coins = gold_pile.choose(rand);
    return try registry.addNewEntity(g.entities.goldPile(coins));
}

const GenerateArmorAndWeaponOptions = struct {
    /// Maximal weight for an item on its peak depth.
    ///
    /// An item is most likely to appear on the depth that matches its average
    /// damage/protection. This value is used when `depth == peak`.
    base_weight: u8,

    /// Weight penalty for each depth step away from the item peak.
    ///
    /// Higher values make items disappear faster when the current dungeon depth
    /// moves away from their intended tier.
    step_weight: u8,

    /// Minimal non-zero weight for an item inside its spawn radius.
    ///
    /// This keeps a small chance of finding a weapon or armor slightly earlier or later than
    /// its main depth, instead of making the distribution too sharp.
    tail_weight: u8,

    /// Maximal distance from the item peak where the item can still appear.
    ///
    /// Outside this radius the spawn weight is `0`.
    radius: u8,

    const armor_options = GenerateArmorAndWeaponOptions{
        .base_weight = 100,
        .step_weight = 50,
        .tail_weight = 5,
        .radius = 2,
    };

    const weapons_options = GenerateArmorAndWeaponOptions{
        .base_weight = 100,
        .step_weight = 45,
        .tail_weight = 3,
        .radius = 3,
    };
};

fn armorOrWeaponWeight(range: p.Range(u8), depth: u8, ops: GenerateArmorAndWeaponOptions) u8 {
    const power: u16 = (@as(u16, range.min) + @as(u16, range.max)) / 2;
    const peak: u8 = @intCast(1 + power / 7);
    const distance = p.diff(depth, peak);

    if (distance > ops.radius) {
        return 0;
    }
    const penalty = ops.step_weight * distance;
    if (penalty >= ops.base_weight) {
        return ops.tail_weight;
    }

    return @max(ops.tail_weight, ops.base_weight - penalty);
}

fn generateArmor(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    var proportions: [g.entities.presets.Armor.count]u8 = undefined;
    for (g.entities.presets.Armor.fields.values, 0..) |components, i| {
        const protection = components.armor.?.protection;
        proportions[i] = armorOrWeaponWeight(protection, depth, .armor_options);
    }
    const idx = rand.weightedIndex(u8, &proportions);

    return try registry.addNewEntity(g.entities.presets.Armor.fields.values[idx].*);
}

fn generateWeapon(registry: *g.Registry, rand: std.Random, depth: u8) !g.Entity {
    var proportions: [g.entities.presets.Weapons.count]u16 = undefined;
    for (g.entities.presets.Weapons.fields.values, 0..) |components, i| {
        const damage = components.weapon.?.damage;
        proportions[i] = armorOrWeaponWeight(damage, depth, .weapons_options);
    }
    const idx = rand.weightedIndex(u16, &proportions);

    return try registry.addNewEntity(g.entities.presets.Weapons.fields.values[idx].*);
}

const food_proportions: [g.entities.presets.Food.count]u8 = blk: {
    const weights: std.enums.EnumMap(g.entities.presets.Food.Tag, u8) = .init(.{
        .apple = 100,
        .dried_fruits = 90,
        .cheese = 80,
        .stale_bread = 80,
        .rat_skewer = 70,
        .jerky = 60,
        .sandwich = 55,
        .stew = 50,
        .cooked_meat = 45,
        .tins = 25,
        .traveler_ration = 24,
        .salted_meat_pack = 20,
        .miners_rations = 18,
        .ancient_preserved_supplies = 10,
        .insect_paste = 8,
        .armadillo_roast = 6,
    });
    var proportions: [g.entities.presets.Food.count]u8 = undefined;
    for (std.enums.values(g.entities.presets.Food.Tag), 0..) |food, i| {
        proportions[i] = weights.getAssertContains(food);
    }
    break :blk proportions;
};

fn generateFood(registry: *g.Registry, rand: std.Random) !g.Entity {
    const idx = rand.weightedIndex(u8, &food_proportions);
    return try registry.addNewEntity(g.entities.presets.Food.get(@enumFromInt(idx)));
}

const potions_proportions: [g.entities.presets.Potions.count]u8 = blk: {
    const weights: std.enums.EnumMap(g.entities.presets.Potions.Tag, u8) = .init(.{
        .healing_potion = 50,
        .poisoning_potion = 10,
        .oil_potion = 30,
    });
    var proportions: [g.entities.presets.Potions.count]u8 = undefined;
    for (std.enums.values(g.entities.presets.Potions.Tag), 0..) |potion, i| {
        proportions[i] = weights.getAssertContains(potion);
    }
    break :blk proportions;
};

fn generatePotion(registry: *g.Registry, rand: std.Random) !g.Entity {
    const idx = rand.weightedIndex(u8, &potions_proportions);
    return try registry.addNewEntity(g.entities.presets.Potions.get(@enumFromInt(idx)));
}

const ammo_proportions: [g.entities.presets.Ammo.count]u8 = blk: {
    const weights: std.enums.EnumMap(g.entities.presets.Ammo.Tag, u8) = .init(.{
        .arrows = 50,
        .bolts = 50,
        .bullets = 30,
    });
    var proportions: [g.entities.presets.Ammo.count]u8 = undefined;
    for (std.enums.values(g.entities.presets.Ammo.Tag), 0..) |ammo, i| {
        proportions[i] = weights.getAssertContains(ammo);
    }
    break :blk proportions;
};

fn generateAmmo(registry: *g.Registry, rand: std.Random) !g.Entity {
    const idx = rand.weightedIndex(u8, &ammo_proportions);
    return try registry.addNewEntity(g.entities.presets.Ammo.get(@enumFromInt(idx)));
}
