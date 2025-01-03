const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.action_system);

const ActionSystem = @This();

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
    pub const Hit = struct {
        target: g.Entity,
        target_health: *c.Health,
        by_weapon: *c.Weapon,
    };
    /// Do nothing, as example, when trying to move to the wall
    do_nothing,
    /// Skip the round
    wait,
    /// Change the state of the entity to sleep
    go_sleep: g.Entity,
    /// Change the state of the entity to chill
    chill: g.Entity,
    /// Change the state of the entity to hunt
    get_angry: g.Entity,
    /// An entity is going to move in the direction
    move: Move,
    /// An entity is going to open a door
    open: g.Entity,
    /// An entity is going to close a door
    close: g.Entity,
    /// An entity which should be hit
    hit: Hit,
    /// An entity is going to take the item
    take: g.Entity,
    /// The player moves from the level to another level
    move_to_level: c.Ladder,
};

/// Handles intentions to do some actions
pub fn doAction(session: *g.GameSession, actor: g.Entity, action: Action, move_speed: MovePoints) anyerror!MovePoints {
    if (std.log.logEnabled(.debug, .action_system) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), actor });
    }
    switch (action) {
        .move => |move| {
            if (session.level.components.getForEntity(actor, c.Position)) |position|
                return doMove(session, actor, position, move.target, move_speed);
        },
        .hit => |hit| {
            return doHit(session, actor, hit.by_weapon, move_speed, hit.target, hit.target_health);
        },
        .open => |door| {
            try session.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
        },
        .close => |door| {
            try session.level.components.setComponentsToEntity(door, g.entities.ClosedDoor);
        },
        .move_to_level => |ladder| {
            try session.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            session.level.components.getForEntityUnsafe(target, c.EnemyState).* = .sleeping;
            try session.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.go_sleep },
            );
        },
        .chill => |target| {
            session.level.components.getForEntityUnsafe(target, c.EnemyState).* = .walking;
            try session.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.relax },
            );
        },
        .get_angry => |target| {
            session.level.components.getForEntityUnsafe(target, c.EnemyState).* = .aggressive;
            try session.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.get_angry },
            );
        },
        else => {},
    }
    return move_speed;
}

fn doMove(
    session: *g.GameSession,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.Action.Move.Target,
    move_speed: MovePoints,
) anyerror!MovePoints {
    const new_place = switch (target) {
        .direction => |direction| from_position.point.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.point.eql(new_place)) return 0;

    if (checkCollision(session, entity, new_place)) |action| {
        return try doAction(session, entity, action, move_speed);
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity == session.level.player),
            .moved_from = from_position.point,
            .target = target,
        },
    };
    from_position.point = new_place;
    try session.events.sendEvent(event);
    return move_speed;
}

fn checkCollision(session: *g.GameSession, actor: g.Entity, place: p.Point) ?Action {
    if (session.level.collisionAt(place)) |obstacle| {
        switch (obstacle) {
            .cell => return .do_nothing,
            .door => |door| return .{ .open = door },
            .entity => |entity| {
                if (session.level.components.getForEntity(entity, c.Health)) |health|
                    if (session.level.components.getForEntity(actor, c.Weapon)) |weapon|
                        return .{ .hit = .{ .target = entity, .target_health = health, .by_weapon = weapon } };
            },
        }
    }
    return null;
}

fn doHit(
    session: *g.GameSession,
    actor: g.Entity,
    actor_weapon: *const c.Weapon,
    actor_speed: MovePoints,
    enemy: g.Entity,
    enemy_health: *c.Health,
) !MovePoints {
    const damage = actor_weapon.generateDamage(session.prng.random());
    log.debug("The entity {d} received damage {d} from {d}", .{ enemy, damage, actor });
    enemy_health.current -= @as(i16, @intCast(damage));
    try session.level.components.setToEntity(
        enemy,
        c.Animation{ .frames = &c.Animation.FramesPresets.hit },
    );
    if (actor == session.level.player) {
        try session.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
    if (enemy_health.current <= 0) {
        log.debug("The entity {d} is died", .{enemy});
        try session.level.removeEntity(enemy);
        try session.events.sendEvent(
            g.events.Event{
                .entity_died = .{ .entity = enemy, .is_player = (enemy == session.level.player) },
            },
        );
    }
    return actor_speed;
}
