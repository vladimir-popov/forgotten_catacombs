const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.systems);

pub fn handleMove(session: *game.GameSession) anyerror!void {
    var itr = session.query.get2(game.Move, game.Sprite);
    while (itr.next()) |components| {
        const entity = components[0];
        const move = components[1];
        const sprite = components[2];
        // try to move:
        const new_position = sprite.position.movedTo(move.direction);
        if (checkCollision(session, new_position)) |obstacle| {
            try session.components.setToEntity(
                entity,
                game.Collision{ .entity = entity, .obstacle = obstacle, .at = new_position },
            );
            try session.components.removeFromEntity(entity, game.Move);
        } else {
            if (!try doMove(session, move, &sprite.position, entity))
                try session.components.removeFromEntity(entity, game.Move);
        }
    }
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

/// Apply move and maybe change position of the screen.
/// Returns true if move should be kept.
fn doMove(session: *game.GameSession, move: *game.Move, position: *p.Point, entity: game.Entity) !bool {
    position.move(move.direction);
    _ = try collectQuickAction(session);

    if (entity != session.player) {
        return false;
    }

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

    if (try collectQuickAction(session)) {
        return move.keep_moving;
    } else {
        return false;
    }
}

fn collectQuickAction(session: *game.GameSession) !bool {
    const position = if (session.components.getForEntity(session.player, game.Sprite)) |player|
        player.position
    else
        return false;
    try session.quick_actions.resize(0);
    var neighbors = session.dungeon.cellsAround(position) orelse return false;
    while (neighbors.next()) |neighbor| {
        if (std.meta.eql(neighbors.cursor, position))
            continue;
        switch (neighbor) {
            .door => |door| try session.quick_actions.append(if (door == .closed) .open else .close),
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
                try session.quick_actions.append(.{ .hit = entity });
            }
        }
    }
    return session.quick_actions.items.len > 0;
}

pub fn handleCollisions(session: *game.GameSession) anyerror!void {
    for (session.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .closed_door => {
                session.dungeon.openDoor(collision.at);
            },
            .entity => |entity| {
                if (session.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (session.components.getForEntity(entity, game.Health)) |_| {
                        if (session.runtime.rand.boolean()) {
                            try session.components.setToEntity(
                                entity,
                                game.Damage{
                                    .entity = entity,
                                    .amount = session.runtime.rand.uintLessThan(u8, 3) + 1,
                                },
                            );
                        } else {
                            try session.components.setToEntity(
                                entity,
                                game.Animation{
                                    .frames = &game.Animation.Presets.miss,
                                    .position = collision.at,
                                },
                            );
                        }
                    }
                }
            },
        }
        _ = try collectQuickAction(session);
    }
    try session.components.removeAll(game.Collision);
}

pub fn handleDamage(session: *game.GameSession) anyerror!void {
    var itr = session.query.get3(game.Damage, game.Health, game.Sprite);
    while (itr.next()) |components| {
        components[2].hp -= @as(i16, @intCast(components[1].amount));
        try session.components.removeFromEntity(components[0], game.Damage);
        try session.components.setToEntity(
            components[0],
            game.Animation{ .frames = &game.Animation.Presets.hit, .position = components[3].position },
        );
        if (components[2].hp <= 0) {
            try session.removeEntity(components[0]);
        }
    }
}
