const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.action_system);

/// Handles intentions to do some actions
pub fn doActions(session: *g.GameSession) !void {
    var itr = session.level.query().get2(c.Action, c.Position);
    while (itr.next()) |components| {
        const entity = components[0];
        const action = components[1];
        const position = components[2];
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action.type), entity });
        switch (action.type) {
            .move => |*move| {
                _ = try handleMoveAction(session, entity, position, move);
            },
            .open => |door| {
                try session.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
                try session.level.setPlacementWithPlayer(session.level.player_placement);
            },
            .close => |door| {
                try session.level.components.setComponentsToEntity(door, g.entities.ClosedDoor);
            },
            .hit => |enemy| {
                if (session.level.components.getForEntity(entity, c.MeleeWeapon)) |weapon| {
                    try session.level.components.setToEntity(
                        enemy,
                        weapon.damage(session.prng.random()),
                    );
                }
            },
            .move_to_level => |ladder| {
                try session.level.components.removeFromEntity(entity, c.Action);
                try session.moveToLevel(ladder);
                // we have to break the function here, because of iterator is
                // invalid now.
                return;
            },
            else => {},
        }
        try session.level.components.removeFromEntity(entity, c.Action);
    }
}

fn handleMoveAction(
    session: *g.GameSession,
    entity: g.Entity,
    position: *c.Position,
    move: *c.Action.Move,
) !bool {
    const new_position = position.point.movedTo(move.direction);
    if (checkCollision(session, new_position)) |obstacle| {
        try session.level.components.setToEntity(
            entity,
            c.Collision{ .entity = entity, .obstacle = obstacle, .at = new_position },
        );
        return false;
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity == session.level.player),
            .moved_from = position.point,
            .moved_to = new_position,
            .direction = move.direction,
        },
    };
    position.point.move(move.direction);
    try session.events.sendEvent(event);
    return true;
}

fn checkCollision(session: *g.GameSession, position: p.Point) ?c.Collision.Obstacle {
    switch (session.level.dungeon.cellAt(position)) {
        .nothing, .wall => return .wall,
        .door => if (session.level.entityAt(position)) |entity| {
            if (session.level.components.getForEntity(entity, c.Door)) |door|
                if (door.state == .closed)
                    return .{ .closed_door = entity };
        },
        .floor => if (session.level.entityAt(position)) |entity| {
            if (session.level.components.getForEntity(entity, c.Health)) |_|
                return .{ .enemy = entity };
        },
    }
    return null;
}
