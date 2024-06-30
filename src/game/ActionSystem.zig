const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.action_system);

/// Handles intentions to do some actions
pub fn doActions(session: *game.GameSession) anyerror!void {
    var itr = session.query.get2(game.Action, game.Sprite);
    while (itr.next()) |components| {
        const actor_entity = components[0];
        const actor_action = components[1];
        const actor_sprite = components[2];
        switch (actor_action.*) {
            .move => |*move| try handleMoveAction(session, actor_entity, actor_sprite, move),
            .open => |door| try session.openDoor(door),
            .close => |door| try session.closeDoor(door),
            .hit => |enemy| {
                try session.components.setToEntity(
                    enemy,
                    game.Damage{
                        .entity = enemy,
                        .amount = session.runtime.rand.uintLessThan(u8, 3),
                    },
                );
                session.target_entity = .{ .entity = enemy };
            },
            else => {}, // TODO do not ignore other actions
        }
        try session.components.removeFromEntity(actor_entity, game.Action);
    }
}

fn handleMoveAction(
    session: *game.GameSession,
    entity: game.Entity,
    sprite: *game.Sprite,
    move: *game.Action.Move,
) !void {
    const new_position = sprite.position.movedTo(move.direction);
    if (checkCollision(session, new_position)) |obstacle| {
        try session.components.setToEntity(
            entity,
            game.Collision{ .entity = entity, .obstacle = obstacle, .at = new_position },
        );
    } else {
        sprite.position.move(move.direction);
        if (entity != session.player) return;

        // keep player on the screen:
        const screen = &session.screen;
        const inner_region = screen.innerRegion();
        if (move.direction == .up and sprite.position.row < inner_region.top_left.row)
            screen.move(move.direction);
        if (move.direction == .down and sprite.position.row > inner_region.bottomRightRow())
            screen.move(move.direction);
        if (move.direction == .left and sprite.position.col < inner_region.top_left.col)
            screen.move(move.direction);
        if (move.direction == .right and sprite.position.col > inner_region.bottomRightCol())
            screen.move(move.direction);
    }
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
