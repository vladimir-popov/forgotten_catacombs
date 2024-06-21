const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.systems);

pub fn render(session: *game.GameSession) anyerror!void {
    const screen = &session.screen;
    // Draw UI
    try session.runtime.drawUI();
    // Draw walls and floor
    try session.runtime.drawDungeon(screen, session.dungeon);
    // Draw quick actions list

    // Draw sprites inside the screen
    for (session.components.getAll(game.Sprite)) |*sprite| {
        if (screen.region.containsPoint(sprite.position)) {
            try session.runtime.drawSprite(screen, sprite);
        }
    }
    // Draw damage
    for (session.components.getAll(game.Damage)) |dmg| {
        if (session.components.getForEntity(dmg.entity, game.Sprite)) |sprite| {
            try session.runtime.drawSprite(screen, &.{ .position = sprite.position, .letter = "*" });
        }
    }
    // Draw stats
    if (session.components.getForEntity(session.player, game.Health)) |health| {
        var buf: [8]u8 = [_]u8{0} ** 8;
        try session.runtime.drawLabel(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.hp}),
            .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 3 },
        );
    }
}

pub fn handleInput(session: *game.GameSession) anyerror!void {
    const btn = try session.runtime.readButtons() orelse return;
    if (btn.toDirection()) |direction| {
        try session.components.setToEntity(session.player, game.Move{
            .direction = direction,
            .keep_moving = false, // btn.state == .double_pressed,
        });
    }
}

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
    try session.quick_actions.resize(0);

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

    if (try collectQuickAction(session, position.*)) {
        return move.keep_moving;
    } else {
        return false;
    }
}

fn collectQuickAction(session: *game.GameSession, position: p.Point) !bool {
    var neighbors = session.dungeon.cellsAround(position) orelse return false;
    while (neighbors.next()) |neighbor| {
        if (std.meta.eql(neighbors.cursor, position))
            continue;
        switch (neighbor) {
            .door => |door| if (door == .closed) try session.quick_actions.append(.open),
            .entity => |entity| try session.quick_actions.append(.{ .hit = entity }),
            else => {},
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
                        }
                    }
                }
            },
        }
    }
    try session.components.removeAll(game.Collision);
}

pub fn handleDamage(session: *game.GameSession) anyerror!void {
    var itr = session.query.get2(game.Damage, game.Health);
    while (itr.next()) |components| {
        log.debug(
            "Make {d} damage to {d} entity with {d} hp",
            .{ components[1].amount, components[0], components[2].hp },
        );
        components[2].hp -= @as(i16, @intCast(components[1].amount));
        try session.components.removeFromEntity(components[0], game.Damage);
        if (components[2].hp <= 0) {
            try session.removeEntity(components[0]);
        }
    }
}
