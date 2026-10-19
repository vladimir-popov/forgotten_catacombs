const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const AllocatorError = std.mem.Allocator.Error;

const log = std.log.scoped(.actions);

const Self = @This();

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("actions", self));
}

pub const ActionResult = enum {
    /// Action successfully happened and move points were spent
    done,
    /// An action lead to the death of the actor
    actor_is_dead,
};

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

/// Handles the action.
pub fn doAction(
    self: *Self,
    actor: g.Entity,
    action: *const g.Action,
) (g.SystemError || g.GameOverError)!ActionResult {
    switch (action.tag) {
        .drink => {
            return try self.drinkPotion(actor, action.payload.drink);
        },
        .eat => {
            try self.eat(actor, action.payload.eat);
            return .done;
        },
        .open_inventory => {
            try self.session().manageInventory();
            return .done;
        },
        .move => {
            const from_position = self.session().registry.getUnsafe(actor, c.Position);
            try self.doMove(actor, from_position, action.payload.move.target);
            return .done;
        },
        .step_in_trap => {
            return try self.stepInTrap(
                actor,
                action.payload.step_in_trap.trap_entity,
                action.payload.step_in_trap.moving_target,
            );
        },
        .disarm_trap => {
            return try self.tryToDisarmTrap(actor, action.payload.disarm_trap);
        },
        .move_to_level => {
            try self.session().movePlayerToLevel(action.payload.move_to_level);
            return .done;
        },
        .hit => switch (try self.session().damage.tryToHit(actor, action.payload.hit)) {
            .target_killed => return .actor_is_dead,
            .no_ammo, .wrong_ammo, .miss, .hit => return .done,
        },
        .open => {
            try self.openDoor(action.payload.open);
            return .done;
        },
        .close => {
            try self.closeDoor(action.payload.close);
            return .done;
        },
        .pickup => {
            try self.pickup(actor, action.payload.pickup);
            return .done;
        },
        .go_sleep => {
            try self.goSleep(action.payload.go_sleep);
            return .done;
        },
        .chill => {
            try self.chill(action.payload.chill);
            return .done;
        },
        .get_angry => {
            try self.getAngry(action.payload.get_angry);
            return .done;
        },
        .modify_recognize => {
            try self.session().modifyRecognize();
            return .done;
        },
        .trade => {
            try self.session().trade(action.payload.trade);
            return .done;
        },
        .wait => {
            try self.session().registry.set(
                actor,
                c.Animation.initStatic(.wait, self.session().player.eql(actor)),
            );
            return .done;
        },
    }
}

noinline fn doMove(
    self: *Self,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.actions.Action.Payload.Move.Target,
) AllocatorError!void {
    if (entity.eql(self.session().player)) {
        try self.session().sendEvent(.{
            .player_moved = .{
                .moved_from = from_position.place,
                .target = target,
            },
        });
    }
    from_position.place = switch (target) {
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
}

/// Attempts to disarm a trap and returns whether the actor survived its effect.
noinline fn tryToDisarmTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
) (g.SystemError || g.GameOverError)!ActionResult {
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
    return .done;
}

/// Moves the actor onto the trap and returns whether the actor survived its effect.
noinline fn stepInTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
    moving_target: g.Action.Payload.Move.Target,
) (g.SystemError || g.GameOverError)!ActionResult {
    const trap: *const c.Trap = self.session().registry.getUnsafe(trap_id, c.Trap);
    const from_position = self.session().registry.get(actor, c.Position).?;
    try self.doMove(actor, from_position, moving_target);
    return try self.handleTrap(actor, trap_id, trap);
}

/// Applies trap damage and shows a pop-up message.
fn handleTrap(
    self: *Self,
    actor: g.Entity,
    trap_id: g.Entity,
    trap: *const c.Trap,
) (g.SystemError || g.GameOverError)!ActionResult {
    log.debug("The entity {d} stepped to the trap {d} {any}", .{ actor.id, trap_id.id, trap });
    try self.session().journal.markTrapAsKnown(trap_id);
    const health = self.session().registry.getUnsafe(actor, c.Health);
    const health_before = health.current_hp;
    const damage_percent: f32 = @floatFromInt(trap.damagePercent().choose(self.session().prng.random()));
    const damage: u8 = @intFromFloat(health.max * damage_percent / 100.0);
    const is_actor_alive = try self.session().damage.applyDamage(trap_id, actor, health, damage);

    // Show pop-up notifications about hit/damage
    if (actor.eql(self.session().player)) {
        const name = g.Description.rawName(&self.session().registry, trap_id);
        try self.session().showPopUpNotification(
            .{ .trap = .{ .name = name, .damage = health_before - health.current_hp } },
        );
    }
    return if (is_actor_alive) .done else .actor_is_dead;
}

/// Consumes a potion and returns whether the actor survived its effects.
fn drinkPotion(self: *Self, actor: g.Entity, potion_id: g.Entity) (g.SystemError || g.GameOverError)!ActionResult {
    const registry = &self.session().registry;
    const potion = registry.getUnsafe(potion_id, c.Potion).*;

    try self.session().journal.markPotionAsKnown(potion);
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(potion_id);
    }
    // remove the item
    defer self.session().registry.removeEntity(potion_id) catch @panic("Error on removing a potion entity");

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
        .acid, .liquid_fire => {
            const health = self.session().registry.getUnsafe(actor, c.Health);
            const k: f32 = 0.7;
            const damage: u8 = @intFromFloat(k * g.utils.ff32(health.max));
            return if (try self.session().damage.applyDamage(potion_id, actor, health, damage))
                .done
            else
                .actor_is_dead;
        },
        .poison, .oil => {
            const health = self.session().registry.getUnsafe(actor, c.Health);
            const k: f32 = if (potion == .poison) 0.5 else 0.2;
            const damage: u8 = @intFromFloat(k * g.utils.ff32(health.current_hp));
            const poison = try self.session().registry.getOrSet(
                actor,
                c.Poison,
                .{ .damage = damage },
            );
            if (poison.damage < damage)
                poison.damage = damage;
        },
        .antidote => {
            try self.session().registry.remove(actor, c.Poison);
        },
        .bouillon => try self.eat(actor, potion_id),
        .spoiled_bouillon => {
            if (self.session().registry.get(actor, c.Hunger)) |hunger| {
                hunger.turns_after_eating +|= 300;
            }
        },
        .water => {
            // do nothing
        },
    }
    return .done;
}

fn eat(self: *Self, actor: g.Entity, food: g.Entity) AllocatorError!void {
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

fn openDoor(self: *Self, door: g.Action.Payload.Door) AllocatorError!void {
    try self.session().registry.set(door.id, c.Door{ .state = .opened });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_opened });
    try self.session().registry.set(door.id, c.Description{ .preset = .opened_door });
    // an opened door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .floor, .place = door.place });
}

fn closeDoor(self: *Self, door: g.Action.Payload.Door) AllocatorError!void {
    try self.session().registry.set(door.id, c.Door{ .state = .closed });
    try self.session().registry.set(door.id, c.Sprite{ .codepoint = g.codepoints.door_closed });
    try self.session().registry.set(door.id, c.Description{ .preset = .closed_door });
    // a closed door has different z-order
    try self.session().registry.set(door.id, c.Position{ .zorder = .obstacle, .place = door.place });
}

fn pickup(self: *Self, actor: g.Entity, item: g.Entity) AllocatorError!void {
    if (self.session().registry.get(item, c.Pile)) |_| {
        try self.session().manageInventory();
    } else if (self.session().registry.get(item, c.Wallet)) |gold_pile| {
        const wallet = self.session().registry.getUnsafe(actor, c.Wallet);
        wallet.money += gold_pile.money;
        try self.session().registry.removeEntity(item);
        self.session().level.removeEntity(item);
    } else {
        const inventory = self.session().registry.getUnsafe(actor, c.Inventory);
        try inventory.items.add(item);
        try self.session().registry.remove(item, c.Position);
        self.session().level.removeEntity(item);
    }
}

fn goSleep(self: *Self, actor: g.Entity) AllocatorError!void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .sleeping;
    try self.session().registry.set(
        actor,
        c.Animation.initStatic(.go_sleep, false),
    );
}

fn chill(self: *Self, actor: g.Entity) AllocatorError!void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .walking;
    try self.session().registry.set(actor, c.Animation.initStatic(.relax, false));
}

fn getAngry(self: *Self, actor: g.Entity) AllocatorError!void {
    self.session().registry.getUnsafe(actor, c.EnemyState).* = .aggressive;
    try self.session().registry.set(actor, c.Animation.initStatic(.get_angry, false));
}
