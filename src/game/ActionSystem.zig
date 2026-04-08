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
    player_weapon: *const c.Weapon,
    target_entity: g.Entity,
) ?g.Action {
    const target_position =
        self.session().registry.get(target_entity, c.Position) orelse return null;

    if (self.session().level.checkPlaceVisibility(target_position.place) != .visible)
        return null;

    if (player_place.eql(target_position.place)) {
        if (g.meta.isItem(&self.session().registry, target_entity)) {
            return .action(.pickup, target_entity);
        }
        if (self.session().registry.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session().level.depth == 0) return null;

            return .action(.move_to_level, ladder.*);
        }
    }

    const is_near4 = player_place.near4(target_position.place);

    if (g.meta.getEnemyType(&self.session().registry, target_entity)) |_| {
        // It's always possible to hit neighbors in 4 directions
        if (is_near4) return .action(.hit, target_entity);

        // Check the achievability of the target
        const distance: u8 = @intFromFloat(player_place.distanceTo(target_position.place));
        if (distance <= player_weapon.max_distance) {
            if (!self.session().level.isObstaclesOnTheLine(player_place, target_position.place))
                return .action(.hit, target_entity);
        }
    }

    if (is_near4) {
        if (self.session().registry.get(target_entity, c.Shop)) |shop| {
            return .action(.trade, shop);
        }
        if (self.session().registry.get(target_entity, c.Description)) |descr| {
            if (descr.preset == .scientist) {
                return .action(.modify_recognize, {});
            }
        }
        if (self.session().registry.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_place.eql(target_position.place)) {
                return null;
            }
            return switch (door.state) {
                .opened => .action(.close, .{ .id = target_entity, .place = target_position.place }),
                .closed => .action(.open, .{ .id = target_entity, .place = target_position.place }),
            };
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
        // how often the entity should be damaged by hunger
        const damage_every_turn: u8 = switch (hunger.level()) {
            .well_fed => 0,
            .hunger => 8,
            .severe_hunger => 5,
            .critical_starvation => 3,
        };

        if (damage_every_turn == 0 or hunger.turns_after_eating % damage_every_turn != 0) continue;

        const health = self.session().registry.get(entity, c.Health) orelse
            std.debug.panic("Entity {d} has Hunger, but doesn't have a Health component", .{entity.id});
        _ = try self.applyDamage(entity, entity, health, 1, .heal);
    }
}

/// Handles intentions to do some actions.
/// The action can be modified during this method.
pub fn doAction(
    self: *Self,
    actor: g.Entity,
    action: *g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    if (std.log.logEnabled(.debug, .actions) and action.tag != .do_nothing) {
        log.debug("Do action {any} by the entity {d}", .{ action, actor.id });
    }

    log.warn("2. doAction {d}", .{self.session().runtime.stackSize()});
    switch (action.tag) {
        .do_nothing => {
            return .declined;
        },
        .drink => {
            return try self.drinkPotion(actor, action, move_points_for_action);
        },
        .eat => {
            return try self.eat(actor, action, move_points_for_action);
        },
        .open_inventory => {
            try self.session().manageInventory();
            return .{ .done = move_points_for_action };
        },
        .move => {
            const from_position = self.session().registry.getUnsafe(actor, c.Position);
            return self.tryToMove(actor, from_position, action, move_points_for_action);
        },
        .step_in_trap => {
            return try self.handleTrap(actor, action, move_points_for_action);
        },
        .move_to_level => {
            try self.session().movePlayerToLevel(action.payload.move_to_level);
            return .{ .done = 0 };
        },
        .hit => {
            return try self.tryToHit(actor, action, move_points_for_action);
        },
        .open => {
            return try self.openDoor(actor, action, move_points_for_action);
        },
        .close => {
            return try self.closeDoor(actor, action, move_points_for_action);
        },
        .pickup => {
            return try self.pickup(actor, action, move_points_for_action);
        },
        .go_sleep => {
            return try self.goSleep(actor, action, move_points_for_action);
        },
        .chill => {
            return try self.chill(actor, action, move_points_for_action);
        },
        .get_angry => {
            return try self.getAngry(actor, action, move_points_for_action);
        },
        .modify_recognize => {
            try self.session().modifyRecognize();
            return .{ .done = move_points_for_action };
        },
        .trade => {
            try self.session().trade(action.payload.trade);
            return .{ .done = move_points_for_action };
        },
        .wait => {
            try self.session().registry.set(
                actor,
                c.Animation{ .preset = .wait, .is_blocked = self.session().player.eql(actor) },
            );
            return .{ .done = move_points_for_action };
        },
    }
}

fn tryToMove(
    self: *Self,
    entity: g.Entity,
    from_position: *c.Position,
    action: *g.Action,
    move_speed: g.MovePoints,
) anyerror!g.actions.ActionResult {
    std.debug.assert(action.tag == .move);
    log.warn("3 tryToMove {d}", .{self.session().runtime.stackSize()});
    const new_place = switch (action.payload.move.target) {
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.place.eql(new_place)) return .declined;

    if (checkCollision(self, new_place, action)) {
        log.debug("Collision lead to {t}", .{action.tag});
        // The action was changed during checking collision.
        // Now, the action should be handled again.
        return .repeat_action_handler;
    }
    try self.doMove(entity, from_position, action.payload.move.target);
    return .{ .done = move_speed };
}

/// If a collision happens, this method changes the action to an actual one
/// and return `true`. Otherwise return `false`, it means that the move is completed.
///
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(self: *Self, place: p.Point, action: *g.Action) bool {
    std.debug.assert(action.tag == .move);
    log.warn("4 checkCollision {d}", .{self.session().runtime.stackSize()});
    switch (self.session().level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return false,

        .entities => |entities| {
            // Check obstacles
            if (entities[c.Position.ZOrder.obstacle.index()]) |entity| {
                if (self.session().registry.get(entity, c.Door)) |_| {
                    action.set(.open, .{ .id = entity, .place = place });
                    return true;
                }

                if (g.meta.getEnemyType(&self.session().registry, entity)) |_| {
                    action.set(.hit, entity);
                    return true;
                }

                if (self.session().registry.get(entity, c.Shop)) |shop| {
                    action.set(.trade, shop);
                    return true;
                }

                if (self.session().registry.get(entity, c.Description)) |descr| {
                    if (descr.preset == .scientist) {
                        action.set(.modify_recognize, {});
                        return true;
                    }
                }

                // the player should not step on the place with entity with z-order = 2
                action.set(.do_nothing, {});
                return true;
            }
            // Check traps
            if (entities[c.Position.ZOrder.trap.index()]) |entity| {
                if (self.session().registry.get(entity, c.Trap)) |trap| {
                    action.set(
                        .step_in_trap,
                        .{ .trap_entity = entity, .trap = trap.*, .moving_target = action.payload.move.target },
                    );
                    return true;
                }
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with z_order < 2
            return false;
        },
    }
    action.set(.do_nothing, {});
    return true;
}

fn doMove(
    self: *Self,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.actions.Action.Payload.Move.Target,
) !void {
    log.warn("4 doMove {d}", .{self.session().runtime.stackSize()});
    try self.session().sendEvent(.{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity.eql(self.session().player)),
            .moved_from = from_position.place,
            .target = target,
        },
    });
    from_position.place = switch (target) {
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
}

// actor - is who is stepping in the trap
// returns true if the actor is dead.
pub fn handleTrap(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const trap_id: g.Entity = action.payload.step_in_trap.trap_entity;
    const trap: c.Trap = action.payload.step_in_trap.trap;
    log.debug("The entity {d} stepped to the trap {d} {any}", .{ actor.id, trap_id.id, trap });
    const protection = self.session().registry.get(actor, c.Protection) orelse &c.Protection.zeros;
    const health = self.session().registry.getUnsafe(actor, c.Health);
    const health_before = health.current_hp;
    const damage = p.Range(u8){
        .min = health.max / 10,
        .max = (health.max + trap.power * health.max) / 10,
    };

    const is_actor_dead = try self.applyEffect(trap_id, trap_id, trap.effect, damage, actor, protection, health);

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player)) {
        const name = try g.meta.rawName(&self.session().registry, trap_id);
        try self.session().showPopUpNotification(
            .{ .trap = .{ .name = name, .damage = health_before - health.current_hp } },
        );
    }
    if (is_actor_dead) {
        return .actor_is_dead;
    } else {
        const from_position = self.session().registry.get(actor, c.Position).?;
        try self.doMove(actor, from_position, action.payload.step_in_trap.moving_target);
        return .{ .done = move_points_for_action };
    }
}

fn tryToHit(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    std.debug.assert(action.tag == .hit);
    log.warn("3. tryToHit {d}", .{self.session().runtime.stackSize()});

    // Validate the weapon
    const weapon_id, const weapon = g.meta.getWeapon(&self.session().registry, actor);
    if (!try self.isValidWeapon(actor, weapon)) {
        return .declined;
    }

    // Calculate and handle evasion
    const target = action.payload.hit;
    if (try self.isMissed(actor, target)) {
        return .{ .done = move_points_for_action };
    }

    const target_health = self.session().registry.getUnsafe(target, c.Health);
    const target_health_before = target_health.current_hp;
    // Break the function because the target is dead
    if (try self.applyWeaponDamage(actor, weapon_id, weapon, target, target_health)) {
        return .{ .done = move_points_for_action };
    }

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .hit = .{ .target = target, .damage = target_health_before - target_health.current_hp } },
        )
    else if (target.eql(self.session().player))
        try self.session().showPopUpNotification(
            .{ .damage = .{ .actor = actor, .damage = target_health_before - target_health.current_hp } },
        );
    return .{ .done = move_points_for_action };
}

fn isValidWeapon(self: *Self, actor: g.Entity, weapon: *const c.Weapon) !bool {
    if (weapon.ammunition_type) |expected_ammo| {
        const ammo_id, const ammo = g.meta.getAmmunition(&self.session().registry, actor) orelse {
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
    return true;
}

fn isMissed(self: *Self, actor: g.Entity, target: g.Entity) !bool {
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
            try self.session().showPopUpNotification(.{ .miss = .{ .target = target } })
        else if (target.eql(self.session().player))
            try self.session().showPopUpNotification(.{ .dodge = .{ .actor = actor } });
        return true;
    }
    return false;
}

fn applyWeaponDamage(
    self: *Self,
    actor: g.Entity,
    weapon_id: g.Entity,
    weapon: *const c.Weapon,
    target: g.Entity,
    target_health: *c.Health,
) !bool {
    log.warn("4. applyWeaponDamage {d}", .{self.session().runtime.stackSize()});
    const target_armor = self.session().registry.get(target, c.Protection) orelse &c.Protection.zeros;

    // we have to copy the whole component, because the enemy can be removed,
    // and the pointer becomes invalid:
    const enemy_experience: c.Experience = self.session().registry.getUnsafe(target, c.Experience).*;

    // Getting an actual effect after applying possible modifications:
    var effects = g.meta.getActualDamage(&self.session().registry, weapon_id, weapon);

    var itr = effects.values.iterator();
    while (itr.next()) |tuple| {
        const is_target_dead =
            try self.applyEffect(actor, weapon_id, tuple.key, tuple.value.*, target, target_armor, target_health);

        // Give an experience to player
        if (is_target_dead and actor.eql(self.session().player)) {
            try self.session().showPopUpNotification(.{ .exp = enemy_experience.asReward() });
            if (try g.meta.addExperience(&self.session().registry, self.session().player, enemy_experience.asReward())) {
                try self.session().showPopUpNotification(.level_up);
            }
        }

        if (is_target_dead) return true;
    }
    return false;
}

/// Applies the effect to the target. Calculates and applies the damage, or increase the target health for the
/// `healing` effect.
///
/// Returns `true` if the target is dead.
fn applyEffect(
    self: *Self,
    /// who applies the effect
    actor: g.Entity,
    /// what is a source of the effect
    source: g.Entity,
    effect_type: c.Effects.Type,
    effect_range: p.Range(u8),
    /// to whom the effect should be applied
    target: g.Entity,
    target_protection: *const c.Protection,
    target_health: *c.Health,
) !bool {
    log.warn("4. applyEffect {d}", .{self.session().runtime.stackSize()});
    switch (effect_type) {
        .heal => {
            try self.heal(actor, effect_range, target, target_health);
            return false;
        },
        else => {
            return try self.applyEffectDamage(
                actor,
                source,
                effect_type,
                effect_range,
                target,
                target_health,
                target_protection,
            );
        },
    }
}

fn heal(
    self: *Self,
    /// who applies the effect
    actor: g.Entity,
    effect_range: p.Range(u8),
    target: g.Entity,
    target_health: *c.Health,
) !void {
    const value = self.session().prng.random().intRangeAtMost(u8, effect_range.min, effect_range.max);
    target_health.current_hp += value;
    target_health.current_hp = @min(target_health.max, target_health.current_hp);
    const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
    try self.session().registry.set(
        target,
        c.Animation{ .preset = .healing, .is_blocked = is_blocked_animation },
    );

    log.debug("Entity {d} recovered up to {d} hp", .{ target.id, value });
}

fn applyEffectDamage(
    self: *Self,
    /// who applies the effect
    actor: g.Entity,
    source: g.Entity,
    effect_type: c.Effects.Type,
    effect_range: p.Range(u8),
    target: g.Entity,
    target_health: *c.Health,
    target_protection: *const c.Protection,
) !bool {
    log.warn("6. applyEffectDamage {d}", .{self.session().runtime.stackSize()});
    const target_defence: p.Range(u8) = target_protection.resistance.values.get(effect_type) orelse .empty;
    const weapon_class =
        if (self.session().registry.get(source, c.Weapon)) |weapon| weapon.class else .primitive;

    const character_factor: f32 = if (self.session().registry.get(actor, c.Stats)) |actor_stats|
        (0.4 * statBonus(actor_stats, weapon_class) + 4.0) / 4.0
    else
        1.0;

    const base_damage: f32 =
        @floatFromInt(self.session().prng.random().intRangeAtMost(u8, effect_range.min, effect_range.max));
    const damage: u8 = @intFromFloat(@round(base_damage * character_factor));
    const absorbed_damage: u8 = self.session().prng.random().intRangeAtMost(
        u8,
        target_defence.min,
        target_defence.max,
    );
    const damage_value: u8 = if (damage > absorbed_damage) damage - absorbed_damage else 1;
    log.debug(
        "Base damage {d}; Character factor {d}; Damage {d}; Absorbed damage {d};",
        .{ base_damage, character_factor, damage, absorbed_damage },
    );
    return try self.applyDamage(actor, target, target_health, damage_value, effect_type);
}

fn statBonus(actor_stats: *const c.Stats, weapon_class: c.Weapon.Class) f32 {
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
    effect_type: c.Effects.Type,
) !bool {
    if (damage_value == 0) return false;
    const orig_health = target_health.current_hp;
    target_health.current_hp -|= damage_value;
    log.info(
        "Entity {d} received {d} {t} damage. HP: {d} -> {d}",
        .{ target.id, damage_value, effect_type, orig_health, target_health.current_hp },
    );

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
            const optional_reward = try g.entities.random.generateReward(
                &self.session().registry,
                self.session().prng.random(),
                .dungeon,
                self.session().level.depth,
                self.session().registry.getUnsafe(self.session().player, c.Experience).level,
            );
            if (optional_reward) |reward| {
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

fn drinkPotion(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const potion_id = action.payload.drink;
    if (g.meta.getPotionType(&self.session().registry, potion_id)) |potion_type| {
        if (self.session().registry.get(potion_id, c.Consumable)) |potion| {
            var itr = potion.effects.values.iterator();
            while (itr.next()) |entry| {
                const effect_type: c.Effects.Type = entry.key;
                const range: p.Range(u8) = entry.value.*;
                if (self.session().registry.get(actor, c.Health)) |health| {
                    const armor_id, const protection = g.meta.getArmor(&self.session().registry, actor);
                    const actual_protection = g.meta.getActualProtection(&self.session().registry, armor_id, protection);
                    try self.session().journal.markPotionAsKnown(potion_type);
                    const is_actor_dead = try self.applyEffect(
                        actor,
                        potion_id,
                        effect_type,
                        range,
                        actor,
                        &actual_protection,
                        health,
                    );
                    if (is_actor_dead) break;
                }
            }
        }
        try self.consume(actor, potion_id, self.session().registry.getUnsafe(potion_id, c.Consumable));
    }
    return .{ .done = move_points_for_action };
}

fn eat(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const food_id = action.payload.eat;
    try self.consume(actor, food_id, self.session().registry.getUnsafe(food_id, c.Consumable));
    return .{ .done = move_points_for_action };
}

fn consume(self: *Self, actor: g.Entity, item: g.Entity, consumable: *const c.Consumable) !void {
    if (self.session().registry.get(actor, c.Hunger)) |hunger| {
        hunger.turns_after_eating -|= consumable.calories;
    }
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(item);
    }
    // remove the potion
    try self.session().registry.removeEntity(item);
}

fn openDoor(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const door = action.payload.open;
    try self.session().registry.set(door.id, c.Door{ .state = .opened });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_opened });
    try self.session().registry.set(door.id, c.Description{ .preset = .opened_door });
    // an opened door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .floor, .place = door.place });
    return .{ .done = move_points_for_action };
}

fn closeDoor(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const door = action.payload.open;
    try self.session().registry.set(door.id, c.Door{ .state = .closed });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_closed });
    try self.session().registry.set(door.id, c.Description{ .preset = .closed_door });
    // a closed door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .obstacle, .place = door.place });
    return .{ .done = move_points_for_action };
}

fn pickup(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const item = action.payload.pickup;
    const inventory = self.session().registry.getUnsafe(self.session().player, c.Inventory);
    if (self.session().registry.get(item, c.Pile)) |_| {
        try self.session().manageInventory();
    } else {
        try inventory.items.add(item);
        try self.session().registry.remove(item, c.Position);
        try self.session().level.removeEntity(item);
    }
    return .{ .done = move_points_for_action };
}

fn goSleep(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const target = action.payload.go_sleep;
    self.session().registry.getUnsafe(target, c.EnemyState).* = .sleeping;
    try self.session().registry.set(
        target,
        c.Animation{ .preset = .go_sleep },
    );
    return .{ .done = move_points_for_action };
}

fn chill(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const target = action.payload.chill;
    self.session().registry.getUnsafe(target, c.EnemyState).* = .walking;
    try self.session().registry.set(
        target,
        c.Animation{ .preset = .relax },
    );
    return .{ .done = move_points_for_action };
}

fn getAngry(
    self: *Self,
    _: g.Entity,
    action: *const g.Action,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const target = action.payload.get_angry;
    self.session().registry.getUnsafe(target, c.EnemyState).* = .aggressive;
    try self.session().registry.set(
        target,
        c.Animation{ .preset = .get_angry },
    );
    return .{ .done = move_points_for_action };
}
