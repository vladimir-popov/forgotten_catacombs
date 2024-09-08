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
                try session.level.components.setToEntity(door, c.Door.opened);
                try session.level.components.setToEntity(
                    door,
                    c.Sprite{ .codepoint = '\'' },
                );
            },
            .close => |door| {
                try session.level.components.setToEntity(door, c.Door.closed);
                try session.level.components.setToEntity(
                    door,
                    c.Sprite{ .codepoint = '+' },
                );
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
    position.point.move(move.direction);
    if (entity != session.player) return true;

    // keep player on the screen:
    const screen = &session.game.render.screen;
    const inner_region = screen.innerRegion();
    if (move.direction == .up and position.point.row < inner_region.top_left.row)
        screen.move(move.direction);
    if (move.direction == .down and position.point.row > inner_region.bottomRightRow())
        screen.move(move.direction);
    if (move.direction == .left and position.point.col < inner_region.top_left.col)
        screen.move(move.direction);
    if (move.direction == .right and position.point.col > inner_region.bottomRightCol())
        screen.move(move.direction);
    return true;
}

fn checkCollision(session: *g.GameSession, position: p.Point) ?c.Collision.Obstacle {
    if (session.level.dungeon.cellAt(position)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .door => if (session.level.entityAt(position)) |entity| {
                if (session.level.components.getForEntity(entity, c.Door)) |door|
                    if (door.* == .closed)
                        return .{ .door = .{ .entity = entity, .state = .closed } }
                    else
                        return null;
            } else {
                return null;
            },
            .floor => if (session.level.entityAt(position)) |entity| {
                if (session.level.components.getForEntity(entity, c.Health)) |_|
                    return .{ .enemy = entity };

                if (session.level.components.getForEntity(entity, c.Ladder)) |_|
                    return null;

                return .{ .item = entity };
            } else {
                return null;
            },
        }
    }
    return .wall;
}
