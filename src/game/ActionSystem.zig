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

    // Any action can be applied only to a visible entity
    if (self.session().level.checkPlaceVisibility(target_position.place) != .visible)
        return null;

    // An action for an entity under the foot
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

    // An action cannot be performed diagonally towards an object
    const is_near4 = player_place.near4(target_position.place);

    // Is it an enemy?
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
        if (self.session().registry.has(target_entity, c.Shop)) {
            return .action(.trade, target_entity);
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
        if (self.session().registry.has(target_entity, c.Trap) and self.session().journal.known_entities.contains(target_entity)) {
            // the player should not be able to disarm a trap staying on it
            if (player_place.eql(target_position.place)) {
                return null;
            }
            return .action(.disarm_trap, target_entity);
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
            .hunger => 15,
            .severe_hunger => 10,
            .critical_starvation => 5,
        };

        if (damage_every_turn == 0 or hunger.turns_after_eating % damage_every_turn != 0) continue;

        const health = self.session().registry.get(entity, c.Health) orelse
            std.debug.panic("Entity {d} has Hunger, but doesn't have a Health component", .{entity.id});
        _ = try self.applyDamage(entity, entity, health, 1);
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
    self.session().runtime.printStackSize(2, "doAction");
    switch (action.tag) {
        .do_nothing => {
            return .declined;
        },
        .drink => {
            return try self.drinkPotion(actor, action.payload.drink, move_points_for_action);
        },
        .eat => {
            return try self.eat(actor, action.payload.eat, move_points_for_action);
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
            return try self.stepInTrap(
                actor,
                action.payload.step_in_trap.trap_entity,
                action.payload.step_in_trap.moving_target,
                move_points_for_action,
            );
        },
        .disarm_trap => {
            return try self.tryToDisarmTrap(actor, action.payload.disarm_trap, move_points_for_action);
        },
        .move_to_level => {
            try self.session().movePlayerToLevel(action.payload.move_to_level);
            return .{ .done = 0 };
        },
        .hit => {
            return try self.tryToHit(actor, action.payload.hit, move_points_for_action);
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
    moving_speed: g.MovePoints,
) anyerror!g.actions.ActionResult {
    std.debug.assert(action.tag == .move);
    self.session().runtime.printStackSize(3, "tryToMove");
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
    return .{ .done = moving_speed };
}

/// If a collision happens, this method changes the action to an actual one
/// and return `true`. Otherwise return `false`, it means that the move is completed.
///
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(self: *Self, place: p.Point, action: *g.Action) bool {
    std.debug.assert(action.tag == .move);
    self.session().runtime.printStackSize(4, "checkCollision");
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

                if (self.session().registry.has(entity, c.Shop)) {
                    action.set(.trade, entity);
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
            if (entities[c.Position.ZOrder.item.index()]) |entity| {
                if (self.session().registry.get(entity, c.Trap)) |_| {
                    action.set(
                        .step_in_trap,
                        .{ .trap_entity = entity, .moving_target = action.payload.move.target },
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
    self.session().runtime.printStackSize(4, "doMove");
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

noinline fn tryToDisarmTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const rand = self.session().prng.random();
    const trap: *const c.Trap = self.session().registry.getUnsafe(trap_id, c.Trap);
    const dex = self.session().registry.getUnsafe(actor, c.Stats).get(.dexterity);
    const mec = self.session().registry.getUnsafe(actor, c.Skills).values.get(.mechanics);
    const chance: f32 = g.meta.disarmChance(dex, mec, trap.*);
    if (rand.float(f32) < chance) {
        if (try self.handleTrap(actor, trap_id, trap))
            return .actor_is_dead;
    } else {
        try self.session().showPopUpNotification(.disarmed_trap);
        try self.session().registry.removeEntity(trap_id);
    }
    return .{ .done = move_points_for_action };
}

noinline fn stepInTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
    moving_target: g.Action.Payload.Move.Target,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const trap: *const c.Trap = self.session().registry.getUnsafe(trap_id, c.Trap);
    if (try self.handleTrap(actor, trap_id, trap)) {
        return .actor_is_dead;
    } else {
        const from_position = self.session().registry.get(actor, c.Position).?;
        try self.doMove(actor, from_position, moving_target);
        return .{ .done = move_points_for_action };
    }
}

/// Applies damage to the actor stepped to the trap, and shows a pop-up message.
///  * actor - who is stepping in the trap.
///  * trap_id - id of the trap.
/// Returns true if the actor is dead.
fn handleTrap(self: *Self, actor: g.Entity, trap_id: g.Entity, trap: *const c.Trap) !bool {
    log.debug("The entity {d} stepped to the trap {d} {any}", .{ actor.id, trap_id.id, trap });
    try self.session().journal.markTrapAsKnown(trap_id);
    const health = self.session().registry.getUnsafe(actor, c.Health);
    const health_before = health.current_hp;
    const damage_percent: f32 = @floatFromInt(trap.damagePercent().choose(self.session().prng.random()));
    const damage: u8 = @intFromFloat(health.max * damage_percent / 100.0);
    const is_actor_dead = try self.applyDamage(trap_id, actor, health, damage);

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player)) {
        const name = try g.Description.rawName(&self.session().registry, trap_id);
        try self.session().showPopUpNotification(
            .{ .trap = .{ .name = name, .damage = health_before - health.current_hp } },
        );
    }
    return is_actor_dead;
}

fn tryToHit(
    self: *Self,
    actor: g.Entity,
    target: g.Entity,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    self.session().runtime.printStackSize(3, "tryToHit");
    const registry = &self.session().registry;
    const rand = self.session().prng.random();

    // Validate the weapon
    const weapon_id, const weapon = g.meta.getWeapon(registry, actor);
    if (!try self.isValidWeapon(actor, weapon)) {
        return .declined;
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
        return .{ .done = move_points_for_action };
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

    if (is_target_dead) return .{ .done = move_points_for_action };

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

fn drinkPotion(
    self: *Self,
    actor: g.Entity,
    potion_id: g.Entity,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const registry = &self.session().registry;
    const potion: c.Potion = registry.getUnsafe(potion_id, c.Potion).*;
    _ = switch (potion) {
        .healing => {
            const health = registry.getUnsafe(actor, c.Health);
            const hp = g.meta.healingPoints(self.session().prng.random(), health.max);
            try self.heal(hp, actor, health);
        },
        .poison => null,
        .oil => null,
    };
    try self.session().journal.markPotionAsKnown(potion);
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(potion_id);
    }
    // remove the item
    try self.session().registry.removeEntity(potion_id);
    return .{ .done = move_points_for_action };
}

fn heal(
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

fn eat(
    self: *Self,
    actor: g.Entity,
    food: g.Entity,
    move_points_for_action: g.MovePoints,
) !g.actions.ActionResult {
    const consumable = self.session().registry.getUnsafe(food, c.Consumable);
    if (self.session().registry.get(actor, c.Hunger)) |hunger| {
        hunger.turns_after_eating -|= consumable.calories;
    }
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(food);
    }
    // remove the entity completely
    try self.session().registry.removeEntity(food);
    return .{ .done = move_points_for_action };
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
