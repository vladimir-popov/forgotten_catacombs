const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.action_system);

pub fn doActions(session: *game.GameSession) anyerror!void {
    var itr = session.query.get2(game.Action, game.Sprite);
    while (itr.next()) |components| {
        const entity = components[0];
        const action = components[1];
        const sprite = components[2];
        switch (action.*) {
            .move => |*move| try handleMoveAction(session, entity, sprite, move),
            .open => |at| session.dungeon.openDoor(at),
            .close => |at| session.dungeon.closeDoor(at),
            .hit => |enemy| {
                if (session.runtime.rand.boolean()) {
                    try session.components.setToEntity(
                        enemy,
                        game.Damage{
                            .entity = enemy,
                            .amount = session.runtime.rand.uintLessThan(u8, 3) + 1,
                        },
                    );
                } else if (session.components.getForEntity(enemy, game.Sprite)) |enemy_sprite| {
                    try session.components.setToEntity(
                        enemy,
                        game.Animation{
                            .frames = &game.Animation.Presets.miss,
                            .position = enemy_sprite.position,
                        },
                    );
                }
            },
            else => {}, // TODO do not ignore other actions
        }
        try session.components.removeFromEntity(entity, game.Action);
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
        try doMove(session, move, &sprite.position, entity);
    }
}

/// Apply move and maybe change position of the screen.
/// Returns true if move should be kept.
fn doMove(session: *game.GameSession, move: *game.Action.Move, position: *p.Point, entity: game.Entity) !void {
    position.move(move.direction);
    if (entity != session.player) return;

    // keep player on the screen:
    const screen = &session.screen;
    const inner_region = screen.innerRegion();
    if (move.direction == .up and position.row < inner_region.top_left.row)
        screen.move(move.direction);
    if (move.direction == .down and position.row > inner_region.bottomRightRow())
        screen.move(move.direction);
    if (move.direction == .left and position.col < inner_region.top_left.col)
        screen.move(move.direction);
    if (move.direction == .right and position.col > inner_region.bottomRightCol())
        screen.move(move.direction);
}

fn checkCollision(session: *game.GameSession, new_position: p.Point) ?game.Collision.Obstacle {
    if (session.dungeon.cellAt(new_position)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .door => |door| if (door == .opened) return null else return .closed_door,
            .entity => |e| return .{ .entity = e },
            .floor => if (session.entityAt(new_position)) |e| return .{ .entity = e } else return null,
        }
    }
    return .wall;
}

pub fn collectQuickAction(session: *game.GameSession) anyerror!void {
    const position = if (session.components.getForEntity(session.player, game.Sprite)) |player|
        player.position
    else
        return;
    var neighbors = session.dungeon.cellsAround(position) orelse return;
    try session.quick_actions.resize(0);
    while (neighbors.next()) |neighbor| {
        switch (neighbor) {
            .door => |door| try session.quick_actions.append(if (door == .closed)
                .{ .open = neighbors.current_place }
            else
                .{ .close = neighbors.current_place }),
            .entity => |entity| try session.quick_actions.append(.{ .take = entity }),
            else => {},
        }
    }
    // TODO improve:
    const sprites = session.components.arrayOf(game.Sprite);
    const region = p.Region{
        .top_left = .{
            .row = @max(position.row - 1, 1),
            .col = @max(position.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    };
    for (sprites.components.items, 0..) |sprite, idx| {
        if (region.containsPoint(sprite.position)) {
            if (sprites.index_entity.get(@intCast(idx))) |entity| {
                if (session.player != entity)
                    try session.quick_actions.append(.{ .hit = entity });
            }
        }
    }
}
