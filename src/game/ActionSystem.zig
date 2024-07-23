const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.action_system);

/// Handles intentions to do some actions
pub fn doActions(session: *game.GameSession) !u8 {
    var used_move_points: u8 = 0;
    var itr = session.query.get2(game.Action, game.Position);
    while (itr.next()) |components| {
        const actor_entity = components[0];
        const actor_action = components[1];
        const actor_position = components[2];
        switch (actor_action.type) {
            .move => |*move| if (try handleMoveAction(session, actor_entity, actor_position, move)) {
                if (session.components.getForEntity(actor_entity, game.MovePoints)) |move_points| {
                    move_points.subtract(actor_action.move_points);
                    used_move_points += actor_action.move_points;
                }
            },
            .open => |door| {
                try session.components.setToEntity(door, game.Door.opened);
                try session.components.setToEntity(
                    door,
                    game.Sprite{ .codepoint = '\'' },
                );
                if (session.components.getForEntity(actor_entity, game.MovePoints)) |move_points| {
                    move_points.subtract(actor_action.move_points);
                    used_move_points += actor_action.move_points;
                }
            },
            .close => |door| {
                try session.components.setToEntity(door, game.Door.closed);
                try session.components.setToEntity(
                    door,
                    game.Sprite{ .codepoint = '+' },
                );
                if (session.components.getForEntity(actor_entity, game.MovePoints)) |move_points| {
                    move_points.subtract(actor_action.move_points);
                    used_move_points += actor_action.move_points;
                }
            },
            .hit => |enemy| {
                if (session.components.getForEntity(session.player, game.MeleeWeapon)) |weapon| {
                    try session.components.setToEntity(
                        enemy,
                        weapon.damage(session.runtime.rand),
                    );
                    if (session.components.getForEntity(actor_entity, game.MovePoints)) |move_points| {
                        move_points.subtract(actor_action.move_points);
                        used_move_points += actor_action.move_points;
                    }
                }
            },
            else => if (session.components.getForEntity(actor_entity, game.MovePoints)) |move_points| {
                move_points.subtract(actor_action.move_points);
                used_move_points += actor_action.move_points;
            },
        }
        try session.components.removeFromEntity(actor_entity, game.Action);
    }
    return used_move_points;
}

fn handleMoveAction(
    session: *game.GameSession,
    entity: game.Entity,
    position: *game.Position,
    move: *game.Action.Move,
) !bool {
    const new_position = position.point.movedTo(move.direction);
    if (checkCollision(session, new_position)) |obstacle| {
        try session.components.setToEntity(
            entity,
            game.Collision{ .entity = entity, .obstacle = obstacle, .at = new_position },
        );
        return false;
    }
    position.point.move(move.direction);
    if (entity != session.player) return true;

    // keep player on the screen:
    const screen = &session.screen;
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
    if (session.dungeon.cellAt(position)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .floor, .door => if (session.entityAt(position)) |entity| {
                if (session.components.getForEntity(entity, game.Door)) |door|
                    if (door.* == .closed)
                        return .{ .door = .{ .entity = entity, .state = .closed } }
                    else
                        return null;

                if (session.components.getForEntity(entity, game.Health)) |_|
                    return .{ .enemy = entity };

                return .{ .item = entity };
            } else {
                return null;
            },
        }
    }
    return .wall;
}
