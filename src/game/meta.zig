//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;

const log = std.log.scoped(.meta);

pub const EnemyType = g.descriptions.Enemies.Enum;
pub const PlayerArchetype = g.descriptions.Archetypes.Enum;
pub const Skill = g.descriptions.Skills.Enum;

/// A numbers of required exp point for level up.
/// The 0 element is a required amount of exp point to get the
/// second level.
pub const Levels = [_]u16{ 200, 500, 1000, 1500, std.math.maxInt(u16) };

pub inline fn experienceToNextLevel(current_level: u4) u16 {
    return Levels[current_level - 1];
}

pub inline fn isLevelUp(registry: *g.Registry, player: g.Entity) bool {
    if (registry.get(player, c.LevelUp)) |level_up| {
        return level_up.last_handled_level < registry.getUnsafe(player, c.Experience).level;
    } else {
        return false;
    }
}

pub fn actualLevel(current_level: u4, total_experience: u16) u4 {
    var level = current_level;
    while (g.meta.Levels[level - 1] < total_experience) {
        level += 1;
    }
    return level;
}

/// Adds exp to the player's Experience. If it leads to level up,
/// increases the player level, updates the LevelUp component for the player,
/// and return `true`. Otherwise returns `false`.
pub fn addExperience(registry: *g.Registry, player: g.Entity, exp: u16) !bool {
    const experience = registry.getUnsafe(player, c.Experience);
    const level_before = experience.level;
    experience.experience +|= exp;
    experience.level = actualLevel(experience.level, experience.experience);
    if (experience.level > level_before) {
        const level_up = try registry.getOrSet(player, c.LevelUp, .{ .last_handled_level = level_before });
        level_up.last_handled_level = @min(level_up.last_handled_level, level_before);
        return true;
    } else {
        return false;
    }
}

pub fn statsFromArchetype(archetype: PlayerArchetype) c.Stats {
    return switch (archetype) {
        .adventurer => .init(0, 0, 0, 0, 0),
        .archeologist => .init(-2, 0, 1, 2, 0),
        .vandal => .init(2, 0, -1, -1, 2),
        .rogue => .init(-1, 2, 1, 0, -1),
    };
}

pub fn getActualStats(registry: *const g.Registry, entity: g.Entity) c.Stats {
    var stats: c.Stats = if (registry.get(entity, c.Stats)) |stats| stats.* else c.Stats.zeros;
    if (registry.get(entity, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon_id| {
            stats.merge(statsFromModifications(registry, weapon_id));
        }
        if (equipment.armor) |armor_id| {
            stats.merge(statsFromModifications(registry, armor_id));
        }
    } else {
        stats.merge(statsFromModifications(registry, entity));
    }
    return stats;
}

fn statsFromModifications(registry: *const g.Registry, entity: g.Entity) c.Stats {
    var stats = c.Stats.zeros;
    if (registry.get(entity, c.Improvements)) |improvements| {
        for (std.enums.values(c.Stats.Stat)) |stat| {
            if (improvements.modifications.contains(stat)) {
                stats.add(stat, 2);
            }
        }
    }
    if (registry.get(entity, c.Breakages)) |breakages| {
        for (std.enums.values(c.Stats.Stat)) |stat| {
            if (breakages.modifications.contains(stat)) {
                stats.add(stat, -2);
            }
        }
    }
    return stats;
}

pub const EntityType = enum { enemy, food, potion, weapon, armor, light, trap };

pub fn getEntityType(registry: *const g.Registry, entity: g.Entity) ?EntityType {
    if (registry.has(entity, c.EnemyState)) return .enemy;
    if (registry.has(entity, c.Weapon)) return .weapon;
    if (registry.has(entity, c.Armor)) return .armor;
    if (registry.has(entity, c.Potion)) return .potion;
    if (registry.has(entity, c.Consumable)) return .food;
    if (registry.has(entity, c.SourceOfLight)) return .light;
    if (registry.has(entity, c.Trap)) return .trap;
    return null;
}

/// An Item is any entity with weight is item.
/// It is something, that could be taken, buying or selling.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Returns a type of the enemy if it has a description preset from an appropriate namespace.
pub inline fn getEnemyType(registry: *const g.Registry, entity: g.Entity) ?EnemyType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(EnemyType, @tagName(descr.preset))
    else
        null;
}

pub fn isEquipped(registry: *const g.Registry, player: g.Entity, item: g.Entity) bool {
    if (registry.get(player, c.Equipment)) |eqp| {
        return item.eql(eqp.weapon) or item.eql(eqp.armor) or item.eql(eqp.light) or item.eql(eqp.ammunition);
    }
    return false;
}

/// Returns the id of the item with maximal radius of light through all equipped sources of the light,
/// or null and default value.
pub fn getLight(registry: *const g.Registry, equipment: *const c.Equipment) struct { ?g.Entity, f32 } {
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
    return .{ null, 1.0 };
}

/// Returns an id of the equipped weapon, or the `actor`, because any enemy must be able to provide
/// a damage without equipment. The player and humanoid enemies should be able to damage by hands,
/// animal should bite (but, hands and tooth are not equipped as a weapon).
pub fn getWeapon(registry: *const g.Registry, actor: g.Entity) struct { g.Entity, *const c.Weapon } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon_id| {
            const weapon = registry.get(weapon_id, c.Weapon) orelse
                std.debug.panic("A Weapon component is not provided for the weapon entity {d}", .{weapon_id.id});
            return .{ weapon_id, weapon };
        }
    }
    // "tooth" and "bare hands" are not equipped weapon,
    // just emulate them
    return .{ actor, registry.getUnsafe(actor, c.Weapon) };
}

/// Collects effects for a weapon from its own property and possible modifications
pub fn getWeaponEffects(
    registry: *const g.Registry,
    weapon_id: g.Entity,
    weapon: *const c.Weapon,
) std.enums.EnumSet(c.ElementalEffect) {
    var effects: std.enums.EnumSet(c.ElementalEffect) = .initEmpty();
    effects.toggleSet(weapon.effects);
    if (registry.get(weapon_id, c.Improvements)) |improvements| {
        var itr = improvements.modifications.iterator();
        while (itr.next()) |eff| {
            switch (eff) {
                .fire => effects.toggle(.fire),
                .poison => effects.toggle(.poison),
                .acid => effects.toggle(.acid),
                else => {},
            }
        }
    }
    return effects;
}

pub fn getProtectionResistances(
    registry: *const g.Registry,
    armor_id: g.Entity,
) std.enums.EnumMap(c.ElementalEffect, c.Resistance) {
    var resistances: std.enums.EnumMap(c.ElementalEffect, c.Resistance) = .initFull(.normal);
    if (registry.get(armor_id, c.Improvements)) |improvements| {
        var itr = improvements.modifications.iterator();
        while (itr.next()) |eff| {
            switch (eff) {
                .fire => resistances.put(.fire, .resist),
                .poison => resistances.put(.poison, .resist),
                .acid => resistances.put(.acid, .resist),
                else => {},
            }
        }
    }
    if (registry.get(armor_id, c.Breakages)) |breakages| {
        var itr = breakages.modifications.iterator();
        while (itr.next()) |eff| {
            switch (eff) {
                .fire => resistances.put(.fire, .weak),
                .poison => resistances.put(.poison, .weak),
                .acid => resistances.put(.acid, .weak),
                else => {},
            }
        }
    }
    return resistances;
}

/// If the actor has equipped armor, this method returns id of the equipped armor and its
/// protection;
/// If the actor has a protection directly (as many enemies do), this method returns the `actor` and
/// its protection;
/// Otherwise the `actor` and null will be returned.
pub fn getArmor(registry: *const g.Registry, actor: g.Entity) struct { g.Entity, ?c.Armor } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.armor) |armor_id| {
            const protection = registry.getUnsafe(armor_id, c.Armor);
            return .{ armor_id, protection.* };
        }
    }
    if (registry.get(actor, c.Armor)) |protection|
        return .{ actor, protection.* };

    return .{ actor, null };
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

pub fn initialHealth(constitution: i4) c.Health {
    const constitution_factor = (@as(f32, @floatFromInt(constitution)) * 0.6 + 4.4) / 4.0;
    return .init(@intFromFloat(@round(constitution_factor * 30)));
}

pub fn movePointsForAction(registry: *const g.Registry, actor: g.Entity, action: g.Action.Tag) g.MovePoints {
    return switch (action) {
        .hit => registry.getUnsafe(actor, c.Speed).atack_speed,
        else => registry.getUnsafe(actor, c.Speed).moving_speed,
    };
}

pub fn hasModifications(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Improvements) or registry.has(entity, c.Breakages);
}

/// Adds an optional effect as an breakage to the item and changes the codepoint of the item to
/// the unknown_codepoint.
/// If the effect is omitted, it will be randomly selected.
pub fn breakItem(
    registry: *g.Registry,
    rand: std.Random,
    item: g.Entity,
    unknown_codepoint: g.Codepoint,
    modified_effect: ?c.Modification,
) !void {
    const is_weapon = registry.has(item, c.Weapon);
    const modification: c.Modification = if (modified_effect) |eff| eff else blk: {
        const proportions = if (is_weapon) c.Breakages.proportions[3..] else &c.Breakages.proportions;
        const idx = rand.weightedIndex(u8, proportions);
        const effect_idx = if (is_weapon) idx + 3 else idx;
        break :blk @as(c.Modification, @enumFromInt(effect_idx));
    };
    const breakages = try registry.getOrSet(item, c.Breakages, .{ .modifications = .initEmpty() });
    breakages.modifications.add(modification);
    log.debug("Add the breakage {t} to {d}", .{ modification, item.id });
    try registry.set(item, c.Sprite{ .codepoint = unknown_codepoint });
}

/// Adds an optional effect as an improvement to the item and changes the codepoint of the item to
/// the unknown_codepoint.
/// If the effect is omitted, it will be randomly selected.
pub fn improveItem(
    registry: *g.Registry,
    rand: std.Random,
    item: g.Entity,
    unknown_codepoint: g.Codepoint,
    modified_effect: ?c.Modification,
) !void {
    const effect = if (modified_effect) |eff| eff else blk: {
        const idx = rand.weightedIndex(u8, &c.Improvements.proportions);
        break :blk @as(c.Modification, @enumFromInt(idx));
    };
    const improvements = try registry.getOrSet(item, c.Improvements, .{ .modifications = .initEmpty() });
    improvements.modifications.add(effect);
    log.debug("Add the improvement {t} to {d}", .{ effect, item.id });
    try registry.set(item, c.Sprite{ .codepoint = unknown_codepoint });
}

pub fn healingPoints(rand: std.Random, max_hp: u8) u8 {
    const percent: f32 = @floatFromInt(rand.intRangeAtMost(u8, 30, 60));
    const max_hp_f: f32 = max_hp;
    return @intFromFloat(max_hp_f * percent / 100.0);
}

pub fn disarmChance(dexterity: i4, mechanic: i4, trap: c.Trap) f32 {
    const dex: f32 = @floatFromInt(dexterity);
    const mech: f32 = @floatFromInt(mechanic);
    const power: f32 = @floatFromInt(trap.power);
    return std.math.clamp(
        0.30 + 0.06 * dex + 0.07 * mech - 0.10 * power,
        0.05,
        0.90,
    );
}

pub fn hitChance(actor_perception: i4, actor_weapon_mastery: i4, target_dexterity: i4) f32 {
    const dex: f32 = @floatFromInt(target_dexterity);
    const per: f32 = @floatFromInt(actor_perception);
    const skill: f32 = @floatFromInt(actor_weapon_mastery);
    return 0.6 + 0.02 * per + 0.02 * skill - 0.03 * dex;
}

pub fn calculateDamage(
    base_damage: u8,
    weapon_class: c.Weapon.Class,
    weapon_effects: std.enums.EnumSet(c.ElementalEffect),
    actor_stats: c.Stats,
    enemy_protection: u8,
    protection_resistances: std.enums.EnumMap(c.ElementalEffect, c.Resistance),
) u8 {
    const str: f32 = @floatFromInt(actor_stats.get(.strength));
    const stat: f32 = @floatFromInt(switch (weapon_class) {
        .primitive => actor_stats.get(.strength),
        .tricky => actor_stats.get(.dexterity),
        .ancient => actor_stats.get(.intelligence),
    });
    const poison_min: f32 = if (weapon_effects.contains(.poison))
        switch (protection_resistances.get(.poison) orelse .normal) {
            .weak => 0.3,
            .normal => 0.2,
            .resist => 0.0,
        }
    else
        0.0;

    const fire_multiplier: f32 = if (weapon_effects.contains(.fire))
        switch (protection_resistances.get(.fire) orelse .normal) {
            .weak => 1.25,
            .normal => 1.1,
            .resist => 1.0,
        }
    else
        1.0;

    const acid_factor: f32 = if (weapon_effects.contains(.acid))
        switch (protection_resistances.get(.acid) orelse .normal) {
            .weak => 0.6,
            .normal => 0.85,
            .resist => 1.0,
        }
    else
        1.0;

    const physical_damage: f32 = base_damage * (1 + 0.1 * stat + 0.05 * str);

    return @intFromFloat(@max(
        poison_min,
        physical_damage * fire_multiplier - enemy_protection * acid_factor,
    ));
}
