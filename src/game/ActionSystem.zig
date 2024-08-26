const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.action_system);

/// Handles intentions to do some actions
pub fn doActions(session: *game.GameSession) !void {
    var itr = session.level.query().get2(game.Action, game.Position);
    while (itr.next()) |components| {
        const entity = components[0];
        const action = components[1];
        const position = components[2];
        switch (action.type) {
            .move => |*move| {
                _ = try handleMoveAction(session, entity, position, move);
            },
            .open => |door| {
                try session.level.components.setToEntity(door, game.Door.opened);
                try session.level.components.setToEntity(
                    door,
                    game.Sprite{ .codepoint = '\'' },
                );
            },
            .close => |door| {
                try session.level.components.setToEntity(door, game.Door.closed);
                try session.level.components.setToEntity(
                    door,
                    game.Sprite{ .codepoint = '+' },
                );
            },
            .hit => |enemy| {
                if (session.level.components.getForEntity(entity, game.MeleeWeapon)) |weapon| {
                    try session.level.components.setToEntity(
                        enemy,
                        weapon.damage(session.prng.random()),
                    );
                }
            },
            .move_to_level => |ladder| {
                try session.level.components.removeFromEntity(entity, game.Action);
                try session.moveToLevel(ladder);
                // we have to break the function here, because of iterator is
                // invalid now.
                return;
            },
            else => {},
        }
        try session.level.components.removeFromEntity(entity, game.Action);
    }
}

fn handleMoveAction(
    session: *game.GameSession,
    entity: game.Entity,
    position: *game.Position,
    move: *game.Action.Move,
) !bool {
    const new_position = position.point.movedTo(move.direction);
    if (checkCollision(session, new_position)) |obstacle| {
        try session.level.components.setToEntity(
            entity,
            game.Collision{ .entity = entity, .obstacle = obstacle, .at = new_position },
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

fn checkCollision(session: *game.GameSession, position: p.Point) ?game.Collision.Obstacle {
    if (session.level.dungeon.cellAt(position)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .door => if (session.level.entityAt(position)) |entity| {
                if (session.level.components.getForEntity(entity, game.Door)) |door|
                    if (door.* == .closed)
                        return .{ .door = .{ .entity = entity, .state = .closed } }
                    else
                        return null;
            } else {
                return null;
            },
            .floor => if (session.level.entityAt(position)) |entity| {
                if (session.level.components.getForEntity(entity, game.Health)) |_|
                    return .{ .enemy = entity };

                if (session.level.components.getForEntity(entity, game.Ladder)) |_|
                    return null;

                return .{ .item = entity };
            } else {
                return null;
            },
        }
    }
    return .wall;
}
