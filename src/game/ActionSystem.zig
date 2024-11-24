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

session: *g.GameSession,

/// Handles intentions to do some actions
pub fn doAction(self: ActionSystem, entity: g.Entity, action: Action, move_speed: MovePoints) anyerror!MovePoints {
    if (std.log.logEnabled(.debug, .action_system) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), entity });
    }
    switch (action) {
        .wait => return move_speed,
        .move => |move| {
            if (self.session.level.components.getForEntity(entity, c.Position)) |position|
                return self.doMove(entity, position, move.target, move_speed);
        },
        .open => |door| {
            try self.session.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
            // opening the door by player can change visible places
            if (entity == self.session.level.player) {
                try self.session.level.updatePlacementWithPlayer(self.session.level.player_placement);
            }
            return move_speed;
        },
        .close => |door| {
            try self.session.level.components.setComponentsToEntity(door, g.entities.ClosedDoor);
            // closing the door by player can change visible places
            if (entity == self.session.level.player) {
                try self.session.level.updatePlacementWithPlayer(self.session.level.player_placement);
            }
            return move_speed;
        },
        .hit => |hit| {
            return self.doHit(entity, hit.by_weapon, move_speed, hit.target, hit.target_health);
        },
        .move_to_level => |ladder| {
            try self.session.moveToLevel(ladder);
        },
        else => {},
    }
    return 0;
}

fn doMove(
    self: ActionSystem,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.Action.Move.Target,
    move_speed: MovePoints,
) anyerror!MovePoints {
    const new_place = switch (target) {
        .direction => |direction| from_position.point.movedTo(direction),
        .new_place => |place| place,
    };
    if (self.checkCollision(entity, new_place)) |action| {
        return try self.doAction(entity, action, move_speed);
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity == self.session.level.player),
            .moved_from = from_position.point,
            .target = target,
        },
    };
    from_position.point = new_place;
    try self.session.events.sendEvent(event);
    return move_speed;
}

fn checkCollision(self: ActionSystem, actor: g.Entity, position: p.Point) ?Action {
    switch (self.session.level.dungeon.cellAt(position)) {
        .nothing, .wall => return .do_nothing,
        .door => if (self.session.level.entityAt(position)) |entity| {
            if (self.session.level.components.getForEntity(entity, c.Door)) |door|
                if (door.state == .closed)
                    return .{ .open = entity };
        },
        .floor => if (self.session.level.entityAt(position)) |entity| {
            if (self.session.level.components.getForEntity(entity, c.Health)) |health|
                if (self.session.level.components.getForEntity(actor, c.Weapon)) |weapon|
                    return .{ .hit = .{ .target = entity, .target_health = health, .by_weapon = weapon } };
        },
    }
    return null;
}

fn doHit(
    self: ActionSystem,
    actor: g.Entity,
    actor_weapon: *const c.Weapon,
    actor_speed: MovePoints,
    enemy: g.Entity,
    enemy_health: *c.Health,
) !MovePoints {
    const damage = actor_weapon.generateDamage(self.session.prng.random());
    log.debug("The entity {d} received damage {d} from {d}", .{ enemy, damage, actor });
    enemy_health.current -= @as(i16, @intCast(damage));
    try self.session.level.components.setToEntity(
        enemy,
        c.Animation{ .frames = &c.Animation.Presets.hit },
    );
    if (actor == self.session.level.player) {
        try self.session.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
    if (enemy_health.current <= 0) {
        log.debug("The entity {d} is died", .{enemy});
        try self.session.level.removeEntity(enemy);
        try self.session.events.sendEvent(
            g.events.Event{
                .entity_died = .{ .entity = enemy, .is_player = (enemy == self.session.level.player) },
            },
        );
    }
    return actor_weapon.actualSpeed(actor_speed);
}
