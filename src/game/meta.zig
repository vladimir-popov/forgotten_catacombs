//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

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

/// Any entity with damage is weapon.
pub inline fn isWeapon(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.WeaponClass);
}

/// Any entity with a `SourceOfLight` is a light.
pub inline fn isLight(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.SourceOfLight);
}

/// Returns a type of a potion if it has description preset from appropriate namespace.
pub inline fn isPotion(registry: *const g.Registry, entity: g.Entity) ?PotionType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(PotionType, @tagName(descr.preset))
    else
        null;
}

/// Returns a type of an enemy if it has description preset from appropriate namespace.
pub inline fn isEnemy(registry: *const g.Registry, entity: g.Entity) ?EnemyType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(EnemyType, @tagName(descr.preset))
    else
        null;
}

/// Only weapon and source of light can be equipped.
pub fn canEquip(registry: *const g.Registry, item: g.Entity) bool {
    return isWeapon(registry, item) or isLight(registry, item);
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
/// animal should bite (but hands and tooth are not equipped as a weapon).
pub fn getWeapon(registry: *const g.Registry, actor: g.Entity) g.Entity {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon| {
            return weapon;
        }
    }
    return actor;
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
