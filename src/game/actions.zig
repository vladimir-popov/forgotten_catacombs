//! This module contains logic to handle actions of the player or NPC.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.actions);

pub const MovePoints = u8;

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = union(enum) {
    pub const Move = struct {
        pub const Target = union(enum) {
            new_place: p.Point,
            direction: p.Direction,
        };
        target: Target,
        keep_moving: bool = false,
    };
    /// Do nothing, as example, when trying to move to the wall
    do_nothing,
    /// Skip the round
    wait,
    /// An entity is going to move in the direction
    move: Move,
    /// An entity is going to open a door
    open: struct { id: g.Entity, place: p.Point },
    /// An entity is going to close a door
    close: struct { id: g.Entity, place: p.Point },
    /// An entity to hit
    hit: g.Entity,
    /// The id of an item that someone is going to take from the floor
    pickup: g.Entity,
    /// The id of a potion to drink it
    drink: g.Entity,
    /// The player moves from the level to another level
    move_to_level: c.Ladder,
    /// Change the state of the entity to sleep
    go_sleep: g.Entity,
    /// Change the state of the entity to chill
    chill: g.Entity,
    /// Change the state of the entity to hunt
    get_angry: g.Entity,
    //
    open_inventory,
    //
    trade: *c.Shop,

    pub fn toString(action: Action) []const u8 {
        return switch (action) {
            .close => "Close",
            .drink => "Drink",
            .hit => "Attack",
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => "Go up",
                .down => "Go down",
            },
            .open => "Open",
            .open_inventory => "Inventory",
            .pickup => "Pickup",
            .trade => "Trade",
            .wait => "Wait",
            .get_angry, .chill, .go_sleep, .do_nothing, .move => "???",
        };
    }

    pub fn eql(self: Action, maybe_other: ?Action) bool {
        if (maybe_other) |other| {
            return std.meta.eql(self, other);
        } else {
            return false;
        }
    }
};

pub fn calculateQuickActionForTarget(
    session: *g.GameSession,
    target_entity: g.Entity,
) ?Action {
    const player_position = session.level.playerPosition();
    const target_position =
        session.entities.registry.get(target_entity, c.Position) orelse return null;

    if (player_position.place.eql(target_position.place)) {
        if (session.entities.isItem(target_entity)) {
            return .{ .pickup = target_entity };
        }
        if (session.entities.registry.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and session.level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
    }

    if (player_position.place.near4(target_position.place)) {
        if (session.entities.isEnemy(target_entity)) {
            return .{ .hit = target_entity };
        }
        if (session.entities.registry.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.place.eql(target_position.place)) {
                return null;
            }
            return switch (door.state) {
                .opened => .{ .close = .{ .id = target_entity, .place = target_position.place } },
                .closed => .{ .open = .{ .id = target_entity, .place = target_position.place } },
            };
        }
        if (session.entities.registry.get(target_entity, c.Shop)) |shop| {
            return .{ .trade = shop };
        }
    }
    return null;
}

/// Handles intentions to do some actions.
/// Returns count of used move points.
/// If returns 0, then it means that action was declined (moving to the wall as example).
pub fn doAction(session: *g.GameSession, actor: g.Entity, action: Action, actor_speed: g.MovePoints) !g.MovePoints {
    if (std.log.logEnabled(.debug, .actions) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), actor.id });
    }
    switch (action) {
        .do_nothing => return 0,
        .drink => |potion_id| {
            if (session.entities.registry.get(potion_id, c.Potion)) |potion| {
                const impacts = try session.entities.registry.getOrSet(actor, c.Impacts, .{});
                impacts.add(&potion.effect);
            }
        },
        .open_inventory => {
            try session.manageInventory();
        },
        .move => |move| {
            if (session.entities.registry.get(actor, c.Position)) |position|
                return doMove(session, actor, position, move.target, actor_speed);
        },
        .hit => |target| {
            try doHit(session, actor, target);
            return actor_speed;
        },
        .open => |door| {
            try session.entities.registry.setComponentsToEntity(door.id, g.entities.openedDoor(door.place));
        },
        .close => |door| {
            try session.entities.registry.setComponentsToEntity(door.id, g.entities.closedDoor(door.place));
        },
        .pickup => |item| {
            const inventory = session.entities.registry.getUnsafe(session.player, c.Inventory);
            if (session.entities.registry.get(item, c.Pile)) |_| {
                try session.manageInventory();
            } else {
                try inventory.items.add(item);
                try session.entities.registry.remove(item, c.Position);
                try session.level.removeEntity(item);
            }
        },
        .move_to_level => |ladder| {
            try session.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            session.entities.registry.getUnsafe(target, c.EnemyState).* = .sleeping;
            try session.entities.registry.set(
                target,
                c.Animation{ .preset = .go_sleep },
            );
        },
        .chill => |target| {
            session.entities.registry.getUnsafe(target, c.EnemyState).* = .walking;
            try session.entities.registry.set(
                target,
                c.Animation{ .preset = .relax },
            );
        },
        .get_angry => |target| {
            session.entities.registry.getUnsafe(target, c.EnemyState).* = .aggressive;
            try session.entities.registry.set(
                target,
                c.Animation{ .preset = .get_angry },
            );
        },
        .trade => |shop| {
            try session.trade(shop);
        },
        .wait => {
            try session.entities.registry.set(actor, c.Animation{ .preset = .wait, .is_blocked = session.player.eql(actor) });
        },
    }
    return actor_speed;
}

fn doMove(
    session: *g.GameSession,
    entity: g.Entity,
    from_position: *c.Position,
    target: Action.Move.Target,
    move_speed: g.MovePoints,
) anyerror!g.MovePoints {
    const new_place = switch (target) {
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.place.eql(new_place)) return 0;

    if (checkCollision(session, new_place)) |action| {
        log.debug("Collision lead to {any}", .{action});
        return try doAction(session, entity, action, move_speed);
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity.eql(session.player)),
            .moved_from = from_position.place,
            .target = target,
        },
    };
    try session.events.sendEvent(event);
    from_position.place = new_place;
    return move_speed;
}

/// Returns an action that should be done because of collision.
/// The `null` means that the move is completed;
/// .do_nothing or any other action means that the move should be aborted, and the action handled;
///
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(session: *g.GameSession, place: p.Point) ?Action {
    switch (session.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return null,

        .entities => |entities| {
            if (entities[2]) |entity| {
                if (session.entities.registry.get(entity, c.Door)) |_|
                    return .{ .open = .{ .id = entity, .place = place } };

                if (session.entities.isEnemy(entity))
                    return .{ .hit = entity };

                if (session.entities.registry.get(entity, c.Shop)) |shop| {
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

fn doHit(
    session: *g.GameSession,
    actor: g.Entity,
    enemy: g.Entity,
) !void {
    const weapon = session.entities.getWeapon(actor) orelse {
        log.err("Actor {d} doesn't have any weapon", .{actor.id});
        return;
    };

    // Applying physical damage
    const damage = session.prng.random().intRangeLessThan(u8, weapon.damage_min, weapon.damage_max);
    session.doDamage(enemy, damage, weapon.damage_type);

    // Applying all effects of the weapon
    if (weapon.effects.len > 0) {
        const impacts = try session.entities.registry.getOrSet(enemy, c.Impacts, .{});
        var itr = weapon.effects.constIterator(0);
        while (itr.next()) |effect| {
            impacts.add(effect);
        }
    }

    // a special case to give to player a chance to notice what happened
    const is_blocked_animation = actor.eql(session.player) or enemy.eql(session.player);
    try session.entities.registry.set(enemy, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
    if (actor.eql(session.player)) {
        try session.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
}
