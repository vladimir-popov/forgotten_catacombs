//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.meta);

pub const PotionType = g.descriptions.Potions.Enum;
pub const EnemyType = g.descriptions.Enemies.Enum;
pub const PlayerArchetype = g.descriptions.Archetypes.Enum;
pub const Skill = g.descriptions.Skills.Enum;

/// A numbers of required exp point for level up.
/// The 0 element is a required amount of exp point to get the
/// second level.
pub const Levels = [_]u16{ 500, 1000, 15000, std.math.maxInt(u16) };

pub inline fn experienceToNextLevel(current_level: u4) u16 {
    return Levels[current_level - 1];
}

/// Any entity with weight is item.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Returns a type of a potion if it has description preset from appropriate namespace.
pub inline fn getPotionType(registry: *const g.Registry, entity: g.Entity) ?PotionType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(PotionType, @tagName(descr.preset))
    else
        null;
}

/// Returns a type of an enemy if it has description preset from appropriate namespace.
pub inline fn getEnemyType(registry: *const g.Registry, entity: g.Entity) ?EnemyType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(EnemyType, @tagName(descr.preset))
    else
        null;
}

/// Returns the id of the item with maximal radius of light through all equipped sources of the light,
/// or null and default value.
pub fn getLight(registry: *const g.Registry, equipment: *const c.Equipment) struct { ?g.Entity, f16 } {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return .{ id, sol.radius };
        }
    }
    if (equipment.weapon) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return .{ id, sol.radius };
        }
    }
    return .{ null, 1.5 };
}

/// Returns an id of the equipped weapon, or the `actor`, because any enemy must be able to provide
/// a damage without weapon. The player and humanoid enemies should be able to damage by hands,
/// animal should bite (but, hands and tooth are not equipped as a weapon).
pub fn getWeapon(registry: *const g.Registry, actor: g.Entity) struct { g.Entity, c.Weapon } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon_id| {
            const weapon = registry.get(weapon_id, c.Weapon) orelse
                std.debug.panic("A Weapon component is not provided for the weapon entity {d}", .{weapon_id.id});
            return .{ weapon_id, weapon.* };
        }
    }
    // "tooth" and "bare hands" are not equipped weapon,
    // just emulate them
    return .{ actor, .melee(.primitive) };
}

pub fn getAmmunition(registry: *const g.Registry, actor: g.Entity) ?struct { g.Entity, *c.Ammunition } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.ammunition) |ammo_id| {
            if (registry.get(ammo_id, c.Ammunition)) |ammo| {
                return .{ ammo_id, ammo };
            }
        }
    }

    // Some animals can spit
    if (registry.get(actor, c.Ammunition)) |ammo| {
        return .{ actor, ammo };
    }

    return null;
}

pub fn getActualEffects(registry: *const g.Registry, weapon_id: g.Entity) c.Effects {
    const effects: *c.Effects = registry.getUnsafe(weapon_id, c.Effects);
    // Merge with modifications
    if (registry.get(weapon_id, c.Modification)) |modifications| {
        modifications.applyTo(effects);
    }
    // Return a copy of the merged effects
    return effects.*;
}

pub fn statsFromArchetype(archetype: PlayerArchetype) c.Stats {
    return switch (archetype) {
        .adventurer => .init(0, 0, 0, 0, 0),
        .archeologist => .init(-2, 0, 1, 2, 0),
        .vandal => .init(2, 0, -1, -1, 2),
        .rogue => .init(-1, 2, 1, 0, -1),
    };
}

pub fn initialHealth(constitution: i4) c.Health {
    const constitution_factor = (@as(f32, @floatFromInt(constitution)) * 0.6 + 4.4) / 4.0;
    return .init(@intFromFloat(@round(constitution_factor * 20)));
}

pub fn movePointsForAction(registry: *const g.Registry, actor: g.Entity, _: g.Action) g.MovePoints {
    // TODO: return different mp for attacks
    return registry.getUnsafe(actor, c.Speed).move_points;
}

/// Algorithm of filling a shop:
/// 1. Build a weighted index for all defined in `g.entities.Items` items according to their rarity;
/// 2. Randomly choose a count of items in the shop: [10, 15]
/// 3. Randomly get items
///    3.1. If the item is a weapon, add a random modification with 20% chance.
pub fn fillShop(shop: *c.Shop, registry: *g.Registry, seed: u64) !void {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();
    const count = rand.uintAtMost(usize, 5) + 10;
    // Build a weighted index for all items according to their rarity:
    var proportions: [g.presets.Items.fields.values.len]u8 = undefined;
    var i: usize = 0;
    var itr = g.presets.Items.iterator();
    while (itr.next()) |item| {
        proportions[i] = @intFromEnum(item.rarity.?);
        i += 1;
    }
    for (0..count) |_| {
        // Choose an item for the shop using the weighted index:
        const item = g.presets.Items.fields.values[rand.weightedIndex(u8, &proportions)];
        const entity = try registry.addNewEntity(item.*);
        // Randomly modify a weapon:
        if (registry.has(entity, c.Weapon) and rand.uintAtMost(u8, 100) < 15) {
            try modifyWeapon(registry, rand, entity, -5, 5);
        }
        try shop.items.add(entity);
    }
}

const weighted_index: [c.Effects.TypesCount]u8 = blk: {
    var wi: [c.Effects.TypesCount]u8 = undefined;
    @memset(&wi, 0);
    wi[@intFromEnum(c.Effects.Type.physical)] = 20;
    wi[@intFromEnum(c.Effects.Type.fire)] = 8;
    wi[@intFromEnum(c.Effects.Type.poison)] = 10;
    wi[@intFromEnum(c.Effects.Type.acid)] = 5;
    break :blk wi;
};

/// Applies a random modification value from the range [`min`, `max`] using the weighted index:
///   - physical = 20;
///   - fire = 8;
///   - poison = 10;
///   - acid = 5;
pub fn modifyWeapon(registry: *g.Registry, rand: std.Random, weapon: g.Entity, min: i8, max: i8) !void {
    try registry.set(weapon, c.Sprite{ .codepoint = g.codepoints.weapon_melee_unknown });
    const effect_type = rand.weightedIndex(u8, &weighted_index);
    const value = rand.intRangeAtMost(i8, min, max);
    const modification = try registry.getOrSet(weapon, c.Modification, .{ .modificators = .initFull(0) });
    modification.modificators.values[effect_type] +|= value;
    log.debug(
        "Add modificator {t} = {d} for {d}",
        .{ @as(c.Effects.Type, @enumFromInt(effect_type)), value, weapon.id },
    );
}
