const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const log = std.log.scoped(.actions);

const Self = @This();

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("actions", self));
}

pub const ActionResult = union(enum) {
    /// Action successfully happened and move points were spent
    done: g.MovePoints,
    /// An action lead to the death of the actor
    actor_is_dead,
};

/// Handles intentions to do some actions.
pub fn doAction(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
    speed: c.Speed,
) !ActionResult {
    switch (action.tag) {
        .drink => {
            try self.drinkPotion(actor, action.payload.drink);
            return .{ .done = speed.moving_speed };
        },
        .eat => {
            try self.eat(actor, action.payload.eat);
            return .{ .done = speed.moving_speed };
        },
        .open_inventory => {
            try self.session().manageInventory();
            return .{ .done = speed.moving_speed };
        },
        .move => {
            const from_position = self.session().registry.getUnsafe(actor, c.Position);
            try self.doMove(actor, from_position, action.payload.move.target);
            return .{ .done = speed.moving_speed };
        },
        .step_in_trap => {
            return if (try self.stepInTrap(
                actor,
                action.payload.step_in_trap.trap_entity,
                action.payload.step_in_trap.moving_target,
            ))
                .{ .done = speed.moving_speed }
            else
                .actor_is_dead;
        },
        .disarm_trap => {
            return if (try self.tryToDisarmTrap(actor, action.payload.disarm_trap))
                .{ .done = speed.moving_speed }
            else
                .actor_is_dead;
        },
        .move_to_level => {
            try self.session().movePlayerToLevel(action.payload.move_to_level);
            return .{ .done = speed.moving_speed };
        },
        .hit => if (try self.session().damage.tryToHit(actor, action.payload.hit)) {
            return .{ .done = speed.atack_speed };
        } else {
            return .actor_is_dead;
        },
        .open => {
            try self.openDoor(action.payload.open);
            return .{ .done = speed.moving_speed };
        },
        .close => {
            try self.closeDoor(action.payload.close);
            return .{ .done = speed.moving_speed };
        },
        .pickup => {
            try self.pickup(actor, action.payload.pickup);
            return .{ .done = speed.moving_speed };
        },
        .go_sleep => {
            try self.goSleep(action.payload.go_sleep);
            return .{ .done = speed.moving_speed };
        },
        .chill => {
            try self.chill(action.payload.chill);
            return .{ .done = speed.moving_speed };
        },
        .get_angry => {
            try self.getAngry(action.payload.get_angry);
            return .{ .done = speed.moving_speed };
        },
        .modify_recognize => {
            try self.session().modifyRecognize();
            return .{ .done = speed.moving_speed };
        },
        .trade => {
            try self.session().trade(action.payload.trade);
            return .{ .done = speed.moving_speed };
        },
        .wait => {
            try self.session().registry.set(
                actor,
                c.Animation{ .preset = .wait, .is_blocked = self.session().player.eql(actor) },
            );
            return .{ .done = speed.moving_speed };
        },
    }
}

pub fn calculateQuickActionForTarget(
    self: *Self,
    player_place: p.Point,
    player_weapon: *const c.Weapon,
    target_entity: g.Entity,
) ?g.Action {
    const registry = &self.session().registry;
    const target_position =
        registry.get(target_entity, c.Position) orelse return null;

    // Any action can be applied only to a visible entity
    if (self.session().level.checkPlaceVisibility(target_position.place) != .visible)
        return null;

    // An action for an entity under the foot
    if (player_place.eql(target_position.place)) {
        if (g.meta.isItem(registry, target_entity)) {
            const inventory = self.session().registry.getUnsafe(self.session().player, c.Inventory);
            if (!inventory.isFull())
                return .action(.pickup, target_entity);
        }
        if (registry.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session().level.depth == 0) return null;

            return .action(.move_to_level, ladder.*);
        }
    }

    // An action cannot be performed diagonally towards an object
    const is_near4 = player_place.near4(target_position.place);

    // Is it an enemy?
    if (g.meta.getEnemyType(registry, target_entity)) |_| {
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
        if (registry.has(target_entity, c.Shop)) {
            return .action(.trade, target_entity);
        }
        if (registry.get(target_entity, c.Description)) |descr| {
            if (descr.preset == .scientist) {
                return .action(.modify_recognize, {});
            }
        }
        if (registry.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_place.eql(target_position.place)) {
                return null;
            }
            return switch (door.state) {
                .opened => .action(.close, .{ .id = target_entity, .place = target_position.place }),
                .closed => .action(.open, .{ .id = target_entity, .place = target_position.place }),
            };
        }
        if (registry.has(target_entity, c.Trap) and self.session().journal.known_entities.contains(target_entity)) {
            // the player should not be able to disarm a trap staying on it
            if (player_place.eql(target_position.place)) {
                return null;
            }
            return .action(.disarm_trap, target_entity);
        }
    }
    return null;
}

/// Handles collisions an returns an actual action happened on moving from `from_place` to the `target`,
/// or `null` if moving is not happening, or impossible.
pub fn actualActionOnMoving(self: *Self, from_place: p.Point, target: g.Action.Payload.Move.Target) ?g.Action {
    const place = target.asPlace(from_place);
    if (from_place.eql(place)) return null;

    switch (self.session().level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return .action(.move, .{ .target = target }),

        .entities => |entities| {
            // Check obstacles
            if (entities[@intFromEnum(c.Position.ZOrder.obstacle)]) |entity| {
                if (self.session().registry.get(entity, c.Door)) |_| {
                    return .action(.open, .{ .id = entity, .place = place });
                }

                if (g.meta.getEnemyType(&self.session().registry, entity)) |_| {
                    return .action(.hit, entity);
                }

                if (self.session().registry.has(entity, c.Shop)) {
                    return .action(.trade, entity);
                }

                if (self.session().registry.get(entity, c.Description)) |descr| {
                    if (descr.preset == .scientist) {
                        return .action(.modify_recognize, {});
                    }
                }

                // the player should not step on the place with entity with z-order = 2
                return null;
            }
            // Check traps
            if (entities[@intFromEnum(c.Position.ZOrder.item)]) |entity| {
                if (self.session().registry.get(entity, c.Trap)) |_| {
                    return .action(.step_in_trap, .{ .trap_entity = entity, .moving_target = target });
                }
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with ZOrder.floor
            return .action(.move, .{ .target = target });
        },
    }
    return null;
}

noinline fn doMove(
    self: *Self,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.actions.Action.Payload.Move.Target,
) !void {
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

/// Returns `false` if the actor is dead.
noinline fn tryToDisarmTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
) !bool {
    const rand = self.session().prng.random();
    const trap: *const c.Trap = self.session().registry.getUnsafe(trap_id, c.Trap);
    const dex = self.session().registry.getUnsafe(actor, c.Stats).get(.dexterity);
    const mec = self.session().registry.getUnsafe(actor, c.Skills).values.get(.mechanics);
    const chance: f32 = g.meta.disarmChance(dex, mec, trap.*);
    if (rand.float(f32) < chance) {
        return try self.handleTrap(actor, trap_id, trap);
    } else {
        try self.session().showPopUpNotification(.disarmed_trap);
        try self.session().registry.removeEntity(trap_id);
    }
    return true;
}

/// Returns `true` if the actor is alive after stepping.
noinline fn stepInTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
    moving_target: g.Action.Payload.Move.Target,
) !bool {
    const trap: *const c.Trap = self.session().registry.getUnsafe(trap_id, c.Trap);
    const from_position = self.session().registry.get(actor, c.Position).?;
    try self.doMove(actor, from_position, moving_target);
    return try self.handleTrap(actor, trap_id, trap);
}

/// Applies damage to the actor stepped to the trap, and shows a pop-up message.
///  * actor - who is stepping in the trap.
///  * trap_id - id of the trap.
/// Returns `false` if the actor is dead.
fn handleTrap(self: *Self, actor: g.Entity, trap_id: g.Entity, trap: *const c.Trap) !bool {
    log.debug("The entity {d} stepped to the trap {d} {any}", .{ actor.id, trap_id.id, trap });
    try self.session().journal.markTrapAsKnown(trap_id);
    const health = self.session().registry.getUnsafe(actor, c.Health);
    const health_before = health.current_hp;
    const damage_percent: f32 = @floatFromInt(trap.damagePercent().choose(self.session().prng.random()));
    const damage: u8 = @intFromFloat(health.max * damage_percent / 100.0);
    const is_actor_alive = try self.session().damage.applyDamage(trap_id, actor, health, damage);

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player)) {
        const name = try g.Description.rawName(&self.session().registry, trap_id);
        try self.session().showPopUpNotification(
            .{ .trap = .{ .name = name, .damage = health_before - health.current_hp } },
        );
    }
    return is_actor_alive;
}

fn drinkPotion(self: *Self, actor: g.Entity, potion_id: g.Entity) !void {
    const registry = &self.session().registry;
    const potion = registry.getUnsafe(potion_id, c.Potion).*;

    // handle consequences
    switch (potion) {
        .healing => {
            const health = self.session().registry.getUnsafe(actor, c.Health);
            try self.session().damage.heal(
                g.meta.healingPoints(self.session().prng.random(), health.max),
                actor,
                health,
            );
        },
        .poison, .oil => {
            const health = self.session().registry.getUnsafe(actor, c.Health);
            const k: f32 = if (potion == .poison) 0.4 else 0.1;
            const damage: u8 = @intFromFloat(k * g.utils.ff32(health.max));
            const poison = try self.session().registry.getOrSet(
                actor,
                c.Poison,
                .{ .damage = damage },
            );
            if (poison.damage < damage)
                poison.damage = damage;
        },
    }

    try self.session().journal.markPotionAsKnown(potion);
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(potion_id);
    }
    // remove the item
    try self.session().registry.removeEntity(potion_id);
}

fn eat(self: *Self, actor: g.Entity, food: g.Entity) !void {
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
}

fn openDoor(self: *Self, door: g.Action.Payload.Door) !void {
    try self.session().registry.set(door.id, c.Door{ .state = .opened });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_opened });
    try self.session().registry.set(door.id, c.Description{ .preset = .opened_door });
    // an opened door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .floor, .place = door.place });
}

fn closeDoor(self: *Self, door: g.Action.Payload.Door) !void {
    try self.session().registry.set(door.id, c.Door{ .state = .closed });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_closed });
    try self.session().registry.set(door.id, c.Description{ .preset = .closed_door });
    // a closed door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .obstacle, .place = door.place });
}

fn pickup(self: *Self, actor: g.Entity, item: g.Entity) !void {
    if (self.session().registry.get(item, c.Pile)) |_| {
        try self.session().manageInventory();
    } else if (self.session().registry.get(item, c.Wallet)) |gold_pile| {
        const wallet = self.session().registry.getUnsafe(actor, c.Wallet);
        wallet.money += gold_pile.money;
        try self.session().registry.removeEntity(item);
        try self.session().level.removeEntity(item);
    } else {
        const inventory = self.session().registry.getUnsafe(actor, c.Inventory);
        try inventory.items.add(item);
        try self.session().registry.remove(item, c.Position);
        try self.session().level.removeEntity(item);
    }
}

fn goSleep(self: *Self, actor: g.Entity) !void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .sleeping;
    try self.session().registry.set(
        actor,
        c.Animation{ .preset = .go_sleep },
    );
}

fn chill(self: *Self, actor: g.Entity) !void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .walking;
    try self.session().registry.set(actor, c.Animation{ .preset = .relax });
}

fn getAngry(self: *Self, actor: g.Entity) !void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .aggressive;
    try self.session().registry.set(actor, c.Animation{ .preset = .get_angry });
}
