const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const log = std.log.scoped(.actions);

const Self = @This();

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("actions", self));
}

pub fn calculateQuickActionForTarget(
    self: *Self,
    player_place: p.Point,
    player_weapon: c.Weapon,
    target_entity: g.Entity,
) ?g.Action {
    const target_position =
        self.session().registry.get(target_entity, c.Position) orelse return null;

    if (self.session().level.checkVisibility(target_position.place) != .visible)
        return null;

    if (player_place.eql(target_position.place)) {
        if (g.meta.isItem(&self.session().registry, target_entity)) {
            return .{ .pickup = target_entity };
        }
        if (self.session().registry.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session().level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
    }

    const is_near4 = player_place.near4(target_position.place);

    if (g.meta.isEnemy(&self.session().registry, target_entity)) |_| {
        // It's always possible to hit neighbors in 4 directions
        if (is_near4) return .{ .hit = target_entity };

        // Check the achievability of the target
        const distance: u8 = @intFromFloat(player_place.distanceTo(target_position.place));
        if (distance <= player_weapon.max_distance) {
            if (!self.session().level.isObstaclesOnTheLine(player_place, target_position.place))
                return .{ .hit = target_entity };
        }
    }

    if (is_near4) {
        if (self.session().registry.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_place.eql(target_position.place)) {
                return null;
            }
            return switch (door.state) {
                .opened => .{ .close = .{ .id = target_entity, .place = target_position.place } },
                .closed => .{ .open = .{ .id = target_entity, .place = target_position.place } },
            };
        }
        if (self.session().registry.get(target_entity, c.Shop)) |shop| {
            return .{ .trade = shop };
        }
    }
    return null;
}

pub fn onTurnCompleted(self: *Self) !void {
    // Regenerate health
    var regen_itr = self.session().registry.query(c.Regeneration);
    while (regen_itr.next()) |tuple| {
        const entity, const regeneration = tuple;
        regeneration.accumulated_turns += 1;
        if (regeneration.accumulated_turns > regeneration.turns_to_increase) {
            regeneration.accumulated_turns = 0;
            const health = self.session().registry.get(entity, c.Health) orelse
                std.debug.panic("Entity {d} has Regeneration, but doesn't have a Health component", .{entity.id});
            health.add(1);
        }
    }
    //  Handle hunger
    var hunger_itr = self.session().registry.query(c.Hunger);
    while (hunger_itr.next()) |tuple| {
        const entity, const hunger = tuple;
        hunger.turns_after_eating +|= 1;
        const turns_to_damage: u8 = switch (hunger.level()) {
            .well_fed => 0,
            .hunger => 8,
            .severe_hunger => 5,
            .critical_starvation => 3,
        };

        if (turns_to_damage == 0 or hunger.turns_after_eating % turns_to_damage != 0) continue;

        const health = self.session().registry.get(entity, c.Health) orelse
            std.debug.panic("Entity {d} has Hunger, but doesn't have a Health component", .{entity.id});
        _ = try self.applyDamage(entity, entity, health, 1, .healing);
    }
}

/// Handles intentions to do some actions.
/// Returns an optional happened action and a count of used move points.
/// Returned null and 0 mp mean that the action was declined (moving to the wall as example).
pub fn doAction(self: *Self, actor: g.Entity, action: g.Action) !struct { ?g.Action, g.MovePoints } {
    if (std.log.logEnabled(.debug, .actions) and action != .do_nothing) {
        log.debug("Do action {any} by the entity {d}", .{ action, actor.id });
    }
    const speed = self.session().registry.get(actor, c.Speed) orelse {
        log.err("The entity {d} doesn't have speed and can't do action.", .{actor.id});
        return error.NotEnoughComponents;
    };
    switch (action) {
        .do_nothing => return .{ null, 0 },
        .drink => |potion_id| if (g.meta.isPotion(&self.session().registry, potion_id)) |potion_type| {
            try self.drinkPotion(actor, potion_id, potion_type);
        },
        .open_inventory => {
            try self.session().manageInventory();
        },
        .move => |move| {
            if (self.session().registry.get(actor, c.Position)) |position|
                return doMove(self, actor, position, move, speed.move_points);
        },
        .move_to_level => |ladder| {
            try self.session().movePlayerToLevel(ladder);
            return .{ action, 0 };
        },
        .hit => |target| if (self.session().registry.get(target, c.Health)) |target_health| {
            if (!try self.tryToHit(actor, target, target_health)) return .{ null, 0 };
        } else {
            return .{ null, 0 };
        },
        .open => |door| {
            try self.session().registry.setComponentsToEntity(door.id, g.entities.openedDoor(door.place));
        },
        .close => |door| {
            try self.session().registry.setComponentsToEntity(door.id, g.entities.closedDoor(door.place));
        },
        .pickup => |item| {
            const inventory = self.session().registry.getUnsafe(self.session().player, c.Inventory);
            if (self.session().registry.get(item, c.Pile)) |_| {
                try self.session().manageInventory();
            } else {
                try inventory.items.add(item);
                try self.session().registry.remove(item, c.Position);
                try self.session().level.removeEntity(item);
            }
        },
        .go_sleep => |target| {
            self.session().registry.getUnsafe(target, c.EnemyState).* = .sleeping;
            try self.session().registry.set(
                target,
                c.Animation{ .preset = .go_sleep },
            );
        },
        .chill => |target| {
            self.session().registry.getUnsafe(target, c.EnemyState).* = .walking;
            try self.session().registry.set(
                target,
                c.Animation{ .preset = .relax },
            );
        },
        .get_angry => |target| {
            self.session().registry.getUnsafe(target, c.EnemyState).* = .aggressive;
            try self.session().registry.set(
                target,
                c.Animation{ .preset = .get_angry },
            );
        },
        .trade => |shop| {
            try self.session().trade(shop);
        },
        .wait => {
            try self.session().registry.set(
                actor,
                c.Animation{ .preset = .wait, .is_blocked = self.session().player.eql(actor) },
            );
        },
    }
    return .{ action, speed.move_points };
}

fn doMove(
    self: *Self,
    entity: g.Entity,
    from_position: *c.Position,
    move: g.Action.Move,
    move_speed: g.MovePoints,
) anyerror!struct { ?g.Action, g.MovePoints } {
    const new_place = switch (move.target) {
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.place.eql(new_place)) return .{ null, 0 };

    if (checkCollision(self, new_place)) |action| {
        log.debug("Collision lead to {s}", .{@tagName(action)});
        return try doAction(self, entity, action);
    }
    const entity_moved_event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity.eql(self.session().player)),
            .moved_from = from_position.place,
            .target = move.target,
        },
    };
    try self.session().events.sendEvent(entity_moved_event);
    from_position.place = new_place;
    return .{ .{ .move = move }, move_speed };
}

/// Returns an action that should be done because of collision.
/// The `null` means that the move is completed;
/// .do_nothing or any other action means that the move should be aborted, and the action handled;
///
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(self: *Self, place: p.Point) ?g.Action {
    switch (self.session().level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return null,

        .entities => |entities| {
            if (entities[2]) |entity| {
                if (self.session().registry.get(entity, c.Door)) |_|
                    return .{ .open = .{ .id = entity, .place = place } };

                if (g.meta.isEnemy(&self.session().registry, entity)) |_|
                    return .{ .hit = entity };

                if (self.session().registry.get(entity, c.Shop)) |shop| {
                    return .{ .trade = shop };
                }

                // the player should not step on the place with entity with z-order = 2
                return .do_nothing;
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with z_order < 2
            return null;
        },
    }
    return .do_nothing;
}

/// Returns `true` if the hit happens.
fn tryToHit(
    self: *Self,
    actor: g.Entity,
    target: g.Entity,
    target_health: *c.Health,
) !bool {
    // Validate the weapon
    const weapon_id, const weapon = g.meta.getWeapon(&self.session().registry, actor);
    if (weapon.ammunition_type) |expected_ammo| {
        const ammo_id, const ammo = g.meta.getAmmunition(&self.session().registry, actor) orelse {
            if (actor.eql(self.session().player))
                try self.session().notify(.no_ammo);
            return false;
        };
        if (ammo.ammunition_type != expected_ammo) {
            if (actor.eql(self.session().player))
                try self.session().notify(.wrong_ammo);
            return false;
        }
        ammo.amount -= 1;
        if (ammo.amount == 0) {
            try self.session().registry.removeEntity(ammo_id);
            if (self.session().registry.get(actor, c.Equipment)) |equipment| {
                if (ammo_id.eql(equipment.ammunition)) {
                    equipment.ammunition = null;
                }
            }
            if (self.session().registry.get(actor, c.Inventory)) |inventory| {
                _ = inventory.items.remove(ammo_id);
            }
        }
    }

    // Calculate and handle evasion
    const actor_weapon_skill: i16 = if (self.session().registry.get(actor, c.Skills)) |skills|
        skills.values.get(.weapon_mastery)
    else
        0;
    const target_dexterity: i16, const target_perception: i16 =
        if (self.session().registry.get(target, c.Stats)) |stats|
            .{ stats.dexterity, stats.perception }
        else
            .{ 0, 0 };

    const evation: i16 = 45 + 6 * target_dexterity + 3 * target_perception - 2 * (10 - actor_weapon_skill);
    const rand = self.session().prng.random().intRangeLessThan(i16, 0, 100);
    if (rand < evation) {
        // Miss
        log.debug(
            "Actor {d} missed by the enemy {d} with evation {d} and rand {d}",
            .{ actor.id, target.id, evation, rand },
        );
        if (actor.eql(self.session().player))
            try self.session().notify(.miss)
        else if (target.eql(self.session().player))
            try self.session().notify(.dodge);
        return true;
    }

    // Calculate and apply the damage
    const target_armor = self.session().registry.get(target, c.Armor) orelse &c.Armor.zeros;
    if (self.session().registry.get(weapon_id, c.Effects)) |effects| {
        const actor_experience = self.session().registry.getUnsafe(actor, c.Experience);
        const enemy_experience = self.session().registry.getUnsafe(target, c.Experience);
        for (effects.items()) |effect| {
            const is_target_dead =
                try self.applyEffect(actor, weapon_id, effect, target, target_armor, target_health);

            if (is_target_dead) {
                const level_before = actor_experience.level;
                actor_experience.add(enemy_experience.asReward());
                if (actor.eql(self.session().player))
                    try self.session().notify(.{ .exp = enemy_experience.asReward() });
                if (actor_experience.level > level_before) {
                    @panic("TODO: HANDLE LEVEL UP");
                }
            }
        }
        return true;
    }
    return true;
}

/// Applies the effect to the target. Calculates and applies the damage, or increase the target health for the
/// `healing` effect.
///
/// Returns `true` if the target is dead.
fn applyEffect(
    self: *Self,
    actor: g.Entity,
    source: g.Entity,
    effect: c.Effect,
    target: g.Entity,
    target_armor: *const c.Armor,
    target_health: *c.Health,
) !bool {
    std.debug.assert(effect.min <= effect.max);

    const target_defence = target_armor.resistance.get(effect.effect_type);
    std.debug.assert(target_defence.min <= target_defence.max);

    switch (effect.effect_type) {
        .physical => {
            const weapon_class =
                if (self.session().registry.get(source, c.Weapon)) |weapon| weapon.class else .primitive;
            const actor_stats = if (self.session().registry.get(actor, c.Stats)) |st| st.* else c.Stats.zeros;
            const base_damage: f32 =
                @floatFromInt(self.session().prng.random().intRangeAtMost(u8, effect.min, effect.max));
            const character_factor: f32 = (0.4 * statBonus(actor_stats, weapon_class) + 4) / 4;
            const damage: u8 = @intFromFloat(@round(base_damage * character_factor));
            const absorbed_damage: u8 = self.session().prng.random().intRangeAtMost(
                u8,
                target_defence.min,
                target_defence.max,
            );
            const damage_value: u8 = @max(1, damage - absorbed_damage);
            log.debug(
                "Base damage {d}; Character factor {d}; Damage {d}; Absorbed damage {d};",
                .{ base_damage, character_factor, damage, absorbed_damage },
            );
            return self.applyDamage(actor, target, target_health, damage_value, effect.effect_type);
        },
        .burning, .corrosion, .poisoning => {
            const base_damage = self.session().prng.random().intRangeAtMost(u8, effect.min, effect.max);
            const absorbed_damage: u8 = self.session().prng.random().intRangeAtMost(
                u8,
                target_defence.min,
                target_defence.max,
            );
            return self.applyDamage(
                actor,
                target,
                target_health,
                base_damage -| absorbed_damage,
                effect.effect_type,
            );
        },
        .healing => {
            const value = self.session().prng.random().intRangeAtMost(u8, effect.min, effect.max);
            target_health.current += value;
            target_health.current = @min(target_health.max, target_health.current);
            const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
            try self.session().registry.set(target, c.Animation{ .preset = .healing, .is_blocked = is_blocked_animation });
            log.debug("Entity {d} recovered up to {d} hp", .{ target.id, value });
        },
    }
    return false;
}

inline fn statBonus(actor_stats: c.Stats, weapon_class: c.Weapon.Class) f32 {
    return @floatFromInt(switch (weapon_class) {
        .primitive => actor_stats.strength,
        .tricky => actor_stats.dexterity,
        .ancient => actor_stats.intelligence,
    });
}

/// Applies precalculated damage. Adds a blocked animation if needed, and invokes `onEntityDied`
/// if the target health becomes 0.
///
/// `true` means that the target is dead
fn applyDamage(
    self: *Self,
    actor: g.Entity,
    target: g.Entity,
    target_health: *c.Health,
    damage_value: u8,
    effect_type: c.Effect.Type,
) !bool {
    if (damage_value == 0) return false;
    const orig_health = target_health.current;
    target_health.current -|= damage_value;
    log.debug(
        "Entity {d} received {t} damage {d}. HP: {d} -> {d}",
        .{ target.id, effect_type, damage_value, orig_health, target_health.current },
    );

    if (effect_type != .healing) {
        if (actor.eql(self.session().player))
            try self.session().notify(
                .{ .hit = .{ .target = target, .damage = damage_value, .damage_type = effect_type } },
            )
        else if (target.eql(self.session().player))
            try self.session().notify(.{ .damage = .{ .damage = damage_value, .damage_type = effect_type } });
    }

    if (self.session().registry.get(target, c.EnemyState)) |_| {
        try self.session().registry.set(target, c.EnemyState.aggressive);
    }

    if (target_health.current == 0) {
        try self.session().onEntityDied(target);
        return true;
    } else {
        // a special case to give to the player a chance to notice what happened
        const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
        try self.session().registry.set(target, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
        return false;
    }
}

fn drinkPotion(self: *Self, actor: g.Entity, potion_id: g.Entity, potion_type: g.meta.PotionType) !void {
    if (self.session().registry.get(potion_id, c.Effects)) |effects| {
        for (effects.items()) |effect| {
            if (self.session().registry.get(actor, c.Health)) |health| {
                const armor = self.session().registry.get(actor, c.Armor) orelse &c.Armor.zeros;
                try self.session().journal.markPotionAsKnown(potion_type);
                const is_actor_dead = try self.applyEffect(actor, potion_id, effect, actor, armor, health);
                if (is_actor_dead) break;
            }
        }
    }
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(potion_id);
    }
    // remove the potion
    try self.session().registry.removeEntity(potion_id);
}
