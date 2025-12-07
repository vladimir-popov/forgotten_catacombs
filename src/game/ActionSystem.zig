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
    target_entity: g.Entity,
) ?g.Action {
    const player_position = self.session().level.playerPosition();
    const target_position =
        self.session().registry.get(target_entity, c.Position) orelse return null;

    if (player_position.place.eql(target_position.place)) {
        if (g.meta.isItem(&self.session().registry, target_entity)) {
            return .{ .pickup = target_entity };
        }
        if (self.session().registry.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session().level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
    }

    if (player_position.place.near4(target_position.place)) {
        if (g.meta.isEnemy(&self.session().registry, target_entity)) |_| {
            return .{ .hit = target_entity };
        }
        if (self.session().registry.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.place.eql(target_position.place)) {
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

/// Handles intentions to do some actions.
/// Returns an optional happened action and a count of used move points.
/// Returned null and 0 mp mean that action was declined (moving to the wall as example).
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
        .drink => |potion_id| {
            if (try self.drinkPotion(actor, potion_id)) return .{ null, 0 };
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
        .hit => |target| {
            return if (try tryToHit(self, actor, target)) .{ null, 0 } else .{ action, speed.move_points };
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
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity.eql(self.session().player)),
            .moved_from = from_position.place,
            .target = move.target,
        },
    };
    try self.session().events.sendEvent(event);
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

/// `true` if the actor is dead
fn tryToHit(
    self: *Self,
    actor: g.Entity,
    enemy: g.Entity,
) !bool {
    const damage, const maybe_effect = try g.meta.getDamage(&self.session().registry, actor);

    // Applying regular damage
    if (try self.doDamage(actor, damage.*, enemy)) return true;

    // Applying an effect of the weapon
    if (maybe_effect) |effect| {
        if (effect.damage()) |dmg|
            if (try self.doDamage(actor, dmg, enemy)) return true;
    }
    return false;
}

/// `true` means that entity is dead
fn doDamage(self: *Self, actor: g.Entity, damage: c.Damage, target: g.Entity) !bool {
    const target_health = self.session().registry.get(target, c.Health) orelse {
        log.err("Actor {d} doesn't have a Health component", .{target.id});
        return error.NotEnoughComponents;
    };
    std.debug.assert(damage.min <= damage.max);
    const value = self.session().prng.random().intRangeAtMost(u8, damage.min, damage.max);
    const orig_health = target_health.current;
    target_health.current -|= value;
    log.debug(
        "Entity {d} received {s} damage {d}. HP: {d} -> {d}",
        .{ target.id, @tagName(damage.damage_type), value, orig_health, target_health.current },
    );
    if (target_health.current == 0) {
        try self.session().onEntityDied(target);
        return true;
    } else {
        // a special case to give to player a chance to notice what happened
        const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
        try self.session().registry.set(target, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
        return false;
    }
}

/// `true` means that the target is dead
fn applyEffect(self: *Self, actor: g.Entity, effect: c.Effect, target: g.Entity) !bool {
    if (effect.damage()) |damage| {
        if (try self.doDamage(actor, damage, target)) return true;
    } else if (effect.effect_type == .healing) {
        const health = self.session().registry.getUnsafe(target, c.Health);
        const value = self.session().prng.random().intRangeAtMost(u8, effect.min, effect.max);
        health.current += value;
        health.current = @min(health.max, health.current);
        const is_blocked_animation = actor.eql(self.session().player) or target.eql(self.session().player);
        try self.session().registry.set(target, c.Animation{ .preset = .healing, .is_blocked = is_blocked_animation });
        log.debug("Entity {d} recovered up to {d} hp", .{ target.id, value });
    }
    return false;
}

/// `true` means that the actor is dead
fn drinkPotion(self: *Self, actor: g.Entity, potion_id: g.Entity) !bool {
    if (self.session().registry.get(potion_id, c.Effect)) |effect| {
        try self.session().journal.markPotionAsKnown(potion_id);
        if (try self.applyEffect(actor, effect.*, actor)) return true;
    }
    // try to remove from the inventory
    if (self.session().registry.get(actor, c.Inventory)) |inventory| {
        _ = inventory.items.remove(potion_id);
    }
    // remove the potion
    try self.session().registry.removeEntity(potion_id);
    return false;
}
