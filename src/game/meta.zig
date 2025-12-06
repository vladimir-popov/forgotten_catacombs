//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Error = error{
    DamageIsNotSpecified,
};

pub const PotionType = g.descriptions.Potions.Enum;
pub const EnemyType = g.descriptions.Enemies.Enum;
pub const PlayerArchetype = g.descriptions.Archetypes.Enum;
pub const Skill = g.descriptions.Skills.Enum;

/// Any entity with weight is item.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Any entity with damage is weapon.
pub inline fn isWeapon(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Damage);
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

/// Returns the radius of the light as a maximal radius of all equipped sources of the light.
pub fn getRadiusOfLight(registry: *const g.Registry, equipment: *const c.Equipment) f16 {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol.radius;
        }
    }
    return 1.5;
}

/// Returns a `Damage` component and optional `Effect` of the currently used weapon.
/// The `actor` must be a player or an enemy,  otherwise the `DamageIsNotSpecified` will be returned.
pub fn getDamage(registry: *const g.Registry, actor: g.Entity) Error!struct { *c.Damage, ?*c.Effect } {
    // creatures can damage directly (rat's tooth as example)
    if (registry.get(actor, c.Damage)) |damage| {
        return .{ damage, registry.get(actor, c.Effect) };
    }
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon| {
            if (registry.get(weapon, c.Damage)) |damage| {
                return .{ damage, registry.get(weapon, c.Effect) };
            }
        }
    }
    return error.DamageIsNotSpecified;
}

pub fn statsFromArchetype(archetype: PlayerArchetype) c.Stats {
    return switch (archetype) {
        .adventurer => .init(0, 0, 0, 0, 0),
        .archeologist => .init(-2, 0, 1, 2, 0),
        .vandal => .init(2, 0, -1, -1, 2),
        .rogue => .init(-1, 2, 1, 0, -1),
    };
}
