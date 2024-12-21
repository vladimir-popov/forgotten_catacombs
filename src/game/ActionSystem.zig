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
pub fn doAction(session: *g.GameSession, entity: g.Entity, action: Action, move_speed: MovePoints) anyerror!MovePoints {
    if (std.log.logEnabled(.debug, .action_system) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), entity });
    }
    switch (action) {
        .wait => return move_speed,
        .move => |move| {
            if (session.level.components.getForEntity(entity, c.Position)) |position|
                return doMove(session, entity, position, move.target, move_speed);
        },
        .open => |door| {
            try session.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
            return move_speed;
        },
        .close => |door| {
            try session.level.components.setComponentsToEntity(door, g.entities.ClosedDoor);
            return move_speed;
        },
        .hit => |hit| {
            return doHit(session, entity, hit.by_weapon, move_speed, hit.target, hit.target_health);
        },
        .move_to_level => |ladder| {
            try session.movePlayerToLevel(ladder);
            return move_speed;
        },
        else => {},
    }
    return 0;
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
    switch (session.level.dungeon.cellAt(place)) {
        .doorway, .floor => {
            var itr = session.level.entityAt(place);
            while (itr.next()) |entity| {
                if (session.level.components.getForEntity(entity, c.Door)) |door| {
                    if (door.state == .closed)
                        return .{ .open = entity };
                }

                if (session.level.components.getForEntity(entity, c.Health)) |health|
                    if (session.level.components.getForEntity(actor, c.Weapon)) |weapon|
                        return .{ .hit = .{ .target = entity, .target_health = health, .by_weapon = weapon } };
            }
        },
        else => return .do_nothing,
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
        c.Animation{ .frames = &c.Animation.Presets.hit },
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
    return actor_weapon.actualSpeed(actor_speed);
}
