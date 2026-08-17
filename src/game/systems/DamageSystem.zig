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
        c.Animation{ .preset = .healing, .is_blocked = is_blocked_animation },
    );

    log.debug("Entity {d} recovered up to {d} hp", .{ target.id, value });
}

/// Applies precalculated damage. Adds a blocked animation if needed, and invokes `onEntityDied`
/// if the target health becomes 0.
///
/// `true` means that the target is dead
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
        try self.session().registry.set(target, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
        return false;
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
        return true;
    }
}

pub fn tryToHit(
    self: *Self,
    actor: g.Entity,
    target: g.Entity,
) !bool {
    const registry = &self.session().registry;
    const rand = self.session().prng.random();

    // Validate the weapon
    const weapon_id, const weapon = g.meta.getWeapon(registry, actor);
    if (!try self.isValidWeapon(actor, weapon)) {
        return false;
    }
    const weapon_damage = rand.intRangeAtMost(u8, weapon.damage.min, weapon.damage.max);

    const actor_stats = g.meta.getActualStats(registry, actor);
    const actor_weapon_skill: i4 = if (self.session().registry.get(actor, c.Skills)) |skills|
        skills.values.get(.weapon_mastery)
    else
        0;
    const target_stats = g.meta.getActualStats(registry, target);

    // Calculate and handle evasion
    const hit_chance = g.meta.hitChance(actor_stats.get(.perception), actor_weapon_skill, target_stats.get(.dexterity));
    if (hit_chance < rand.float(f32)) {
        // -- Miss --
        if (actor.eql(self.session().player))
            try self.session().showPopUpNotification(.{ .miss = .{ .target = target } })
        else if (target.eql(self.session().player))
            try self.session().showPopUpNotification(.{ .dodge = .{ .actor = actor } });
        return true;
    }

    const armor_id, const armor = g.meta.getArmor(registry, target);
    const target_protection = if (armor) |arm|
        rand.intRangeAtMost(u8, arm.protection.min, arm.protection.max)
    else
        0;
    const target_health = registry.getUnsafe(target, c.Health);
    const target_health_before = target_health.current_hp;

    const weapon_effects = g.meta.getWeaponEffects(registry, weapon_id, weapon);
    const protection_resistances = g.meta.getProtectionResistances(registry, armor_id);
    const damage = g.meta.calculateDamage(
        weapon_damage,
        weapon.class,
        weapon_effects,
        actor_stats,
        target_protection,
        protection_resistances,
    );

    // we have to copy the whole component, because the enemy can be removed,
    // and the pointer becomes invalid:
    const enemy_experience: c.Experience = self.session().registry.getUnsafe(target, c.Experience).*;

    const is_target_dead =
        try self.applyDamage(actor, target, target_health, damage);

    // Give an experience to player
    if (is_target_dead and actor.eql(self.session().player)) {
        try self.session().showPopUpNotification(.{ .exp = enemy_experience.asReward() });
        if (try g.meta.addExperience(registry, self.session().player, enemy_experience.asReward())) {
            try self.session().showPopUpNotification(.level_up);
        }
    }

    if (is_target_dead) return true;

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .hit = .{ .target = target, .damage = target_health_before - target_health.current_hp } },
        )
    else if (target.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .damage = .{ .actor = actor, .damage = target_health_before - target_health.current_hp } },
        );
    return true;
}

/// Checks where the weapon is melee or has appropriate ammo
fn isValidWeapon(self: *Self, actor: g.Entity, weapon: *const c.Weapon) !bool {
    if (weapon.ammunition_type) |expected_ammo| {
        const registry = &self.session().registry;
        const ammo_id, const ammo = g.meta.getAmmunition(registry, actor) orelse {
            if (actor.eql(self.session().player))
                try self.session().showPopUpNotification(.no_ammo);
            return false;
        };
        if (ammo.ammunition_type != expected_ammo) {
            if (actor.eql(self.session().player))
                try self.session().showPopUpNotification(.wrong_ammo);
            return false;
        }
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
    return true;
}
