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
        if (std.log.logEnabled(.debug, .action_system) and action.type != .undefined) {
            log.debug("Do action {s}({d}) by the entity {d}", .{ @tagName(action.type), action.move_points, entity });
        }
        switch (action.type) {
            .move => |move| {
                _ = try handleMoveAction(session, entity, position, move.target);
            },
            .open => |door| {
                try session.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
                // opening the door can change visible places
                try session.level.updatePlacementWithPlayer(session.level.player_placement);
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
                try session.level.components.setToEntity(entity, c.Action{ .type = .undefined, .move_points = 0 });
                try session.moveToLevel(ladder);
                // we have to break the function here, because of iterator is
                // invalid now.
                return;
            },
            else => {},
        }
        try session.level.components.setToEntity(entity, c.Action{ .type = .undefined, .move_points = 0 });
    }
}

fn handleMoveAction(
    session: *g.GameSession,
    entity: g.Entity,
    position: *c.Position,
    target: c.Action.Move.Target,
) !bool {
    const new_place = switch (target) {
        .direction => |direction| position.point.movedTo(direction),
        .new_place => |place| place,
    };
    if (checkCollision(session, new_place)) |obstacle| {
        try session.level.components.setToEntity(
            entity,
            c.Collision{ .entity = entity, .obstacle = obstacle, .at = new_place },
        );
        return false;
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity == session.level.player),
            .moved_from = position.point,
            .target = target,
        },
    };
    position.point = new_place;
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
