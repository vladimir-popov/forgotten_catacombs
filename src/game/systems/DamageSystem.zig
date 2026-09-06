const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const log = std.log.scoped(.damage);

const Self = @This();

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("damage", self));
}

pub fn heal(
    self: *Self,
    value: u8,
    target: g.Entity,
    target_health: *c.Health,
) !void {
    target_health.current_hp += value;
    target_health.current_hp = @min(target_health.max, target_health.current_hp);
    const is_blocked_animation = target.eql(self.session().player);
    try self.session().registry.set(
        target,
        c.Animation.initStatic(.healing, is_blocked_animation),
    );

    log.debug("Entity {d} recovered up to {d} hp", .{ target.id, value });
}

/// Applies precalculated damage. Adds a blocked animation if needed, and invokes `onEntityDied`
/// if the target health becomes 0.
///
/// `false` means that the target is dead
pub fn applyDamage(
    self: *Self,
    actor: g.Entity,
    target: g.Entity,
    target_health: *c.Health,
    damage_value: u8,
) !bool {
    if (damage_value == 0) return false;
    target_health.current_hp -|= damage_value;
    if (self.session().registry.get(target, c.EnemyState)) |_| {
        try self.session().registry.set(target, c.EnemyState.aggressive);
    }

    if (target_health.current_hp > 0) {
        // a special case to give to the player a chance to notice what happened
        const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
        if (self.session().registry.get(target, c.Animation)) |animation| {
            animation.addHitAnimation(is_blocked_animation);
        } else {
            try self.session().registry.set(target, c.Animation.initStatic(.hit, is_blocked_animation));
        }
        return true;
    } else {
        // handle the death

        // If the enemy was killed by the player...
        if (actor.eql(self.session().player)) {
            // ... we should mark it as known
            if (g.meta.getEnemyType(&self.session().registry, target)) |enemy_type|
                try self.session().journal.markEnemyAsKnown(enemy_type);
            // ...and try to generate a reward
            const rand = self.session().prng.random();
            if (rand.uintAtMost(u8, 100) < 30) {
                const reward = try g.entities.generators.generateReward(
                    &self.session().registry,
                    self.session().prng.random(),
                    self.session().level.depth,
                );
                const place = self.session().registry.getUnsafe(target, c.Position).place;
                const is_dropped = try self.session().level.tryToPutItem(reward, place);
                if (is_dropped)
                    log.debug("Dropped reward {d} at {any}", .{ reward.id, place });
            }
        }

        try self.session().removeDeadEntity(target);
        return false;
    }
}

/// Returns `false` if the target is dead.
pub fn tryToHit(self: *Self, actor: g.Entity, target: g.Entity) !bool {
    const registry = &self.session().registry;
    const rand = self.session().prng.random();

    const weapon_id, const weapon = g.meta.getWeapon(registry, actor);

    // Validate the weapon and handle a shot
    if (weapon.ammunition_type) |expected_ammo| {
        const ammo_id, const ammo = g.meta.getAmmunition(registry, actor) orelse {
            if (actor.eql(self.session().player))
                try self.session().showPopUpNotification(.no_ammo);
            return true;
        };
        if (ammo.ammunition_type != expected_ammo) {
            if (actor.eql(self.session().player))
                try self.session().showPopUpNotification(.wrong_ammo);
            return true;
        }
        const actor_position = registry.getUnsafe(actor, c.Position);
        const target_position = registry.getUnsafe(target, c.Position);
        try registry.set(target, c.Animation.initShot(actor_position.place, target_position.place));
        ammo.amount -= 1;
        if (ammo.amount == 0) {
            try registry.removeEntity(ammo_id);
            if (registry.get(actor, c.Equipment)) |equipment| {
                if (ammo_id.eql(equipment.ammunition)) {
                    equipment.ammunition = null;
                }
            }
            if (registry.get(actor, c.Inventory)) |inventory| {
                _ = inventory.items.remove(ammo_id);
            }
        }
    }

    // Calculate and handle evasion
    const actor_stats = g.meta.getActualStats(registry, actor);
    const actor_weapon_skill: i4 = if (self.session().registry.get(actor, c.Skills)) |skills|
        skills.values.get(.weapon_mastery)
    else
        0;
    const target_stats = g.meta.getActualStats(registry, target);

    const hit_chance = g.meta.hitChance(actor_stats.get(.perception), actor_weapon_skill, target_stats.get(.dexterity));
    if (hit_chance < rand.float(f32)) {
        // -- Miss --
        if (actor.eql(self.session().player))
            try self.session().showPopUpNotification(.{ .miss = .{ .target = target } })
        else if (target.eql(self.session().player))
            try self.session().showPopUpNotification(.{ .dodge = .{ .actor = actor } });
        return true;
    }

    // Calculate the damage
    const weapon_damage = rand.intRangeAtMost(u8, weapon.damage.min, weapon.damage.max);
    const armor_id, const armor = g.meta.getArmor(registry, target);
    const target_protection = if (armor) |arm|
        rand.intRangeAtMost(u8, arm.protection.min, arm.protection.max)
    else
        0;
    const target_health = registry.getUnsafe(target, c.Health);
    const target_health_before = target_health.current_hp;

    const weapon_effects = g.meta.getWeaponEffects(registry, weapon_id, weapon);
    const protection_resistances = g.meta.getProtectionResistances(registry, armor_id);
    const damage = calculateDamage(
        @floatFromInt(weapon_damage),
        weapon.class,
        weapon_effects,
        actor_stats,
        target_protection,
        protection_resistances,
    );

    // we have to copy the whole component, because the enemy can be removed,
    // and the pointer becomes invalid:
    const enemy_experience: c.Experience = self.session().registry.getUnsafe(target, c.Experience).*;

    const is_target_alive =
        try self.applyDamage(actor, target, target_health, damage);

    // Give an experience to player
    if (!is_target_alive and actor.eql(self.session().player)) {
        try self.session().showPopUpNotification(.{ .exp = enemy_experience.asReward() });
        if (try g.meta.addExperience(registry, self.session().player, enemy_experience.asReward())) {
            try self.session().showPopUpNotification(.level_up);
        }
    }

    if (!is_target_alive) return false;

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .hit = .{ .target = target, .damage = target_health_before - target_health.current_hp } },
        )
    else if (target.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .damage = .{ .actor = actor, .damage = target_health_before - target_health.current_hp } },
        );
    return is_target_alive;
}

fn calculateDamage(
    base_damage: f32,
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
        .native => 0,
    });

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

    const poison_min: f32 = if (weapon_effects.contains(.poison))
        switch (protection_resistances.get(.poison) orelse .normal) {
            .weak => 0.3 * base_damage,
            .normal => 0.2 * base_damage,
            .resist => 0.0,
        }
    else
        0.0;

    const physical_damage: f32 = base_damage * (1 + 0.1 * stat + 0.05 * str);

    return @intFromFloat(@max(poison_min, physical_damage * fire_multiplier - enemy_protection * acid_factor));
}
