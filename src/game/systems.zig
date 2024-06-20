const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.systems);

pub fn render(session: *game.GameSession) anyerror!void {
    const screen = &session.screen;

    try session.runtime.drawUI();

    try session.runtime.drawDungeon(screen, session.dungeon);

    var itr = session.query.get2(game.Sprite, game.Position);
    while (itr.next()) |components| {
        if (screen.region.containsPoint(components[2].point)) {
            try session.runtime.drawSprite(screen, components[1], components[2]);
        }
    }

    if (session.components.getForEntity(session.player, game.Health)) |health| {
        var buf: [8]u8 = [_]u8{0} ** 8;
        try session.runtime.drawLabel(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.health}),
            2,
            game.DISPLAY_DUNG_COLS + 3,
        );
    }
}

pub fn handleInput(session: *game.GameSession) anyerror!void {
    const btn = try session.runtime.readButtons() orelse return;
    if (session.components.getForEntity(session.player, game.Move)) |move| {
        if (btn.toDirection()) |direction| {
            move.direction = direction;
            move.keep_moving = btn.state == .double_pressed;
        }
    }
}

const Obstacle = union(enum) {
    closed_door,
    wall,
    entity: game.Entity,
};

pub fn handleMove(session: *game.GameSession) anyerror!void {
    var itr = session.query.get2(game.Move, game.Position);
    while (itr.next()) |components| {
        const entity = components[0];
        const move = components[1];
        const position = components[2];
        if (move.direction) |direction| {
            // try to move:
            const new_point = position.point.movedTo(direction);
            if (handledCollision(session, entity, new_point)) {
                doMove(session, move, position, entity);
            } else {
                move.cancel();
            }
        }
    }
}

/// Should return true if it possible for entity to move to the new_point
fn handledCollision(session: *game.GameSession, entity: game.Entity, new_point: p.Point) bool {
    _ = entity;
    if (collision(session, new_point)) |obstacle| {
        switch (obstacle) {
            .wall => return false,
            .closed_door => {
                session.dungeon.openDoor(new_point);
                return false;
            },
            .entity => {
                return false;
            },
        }
    } else {
        return true;
    }
}

fn collision(session: *game.GameSession, new_point: p.Point) ?Obstacle {
    if (session.dungeon.cellAt(new_point)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .door => |door| if (door == .opened) return null else return .closed_door,
            .entity => |e| return .{ .entity = e },
            .floor => if (entityAt(session, new_point)) |e| return .{ .entity = e } else return null,
        }
    }
    return .wall;
}

fn entityAt(session: *game.GameSession, place: p.Point) ?game.Entity {
    for (session.components.arrayOf(game.Position).components.items, 0..) |pos, idx| {
        if (pos.point.eql(place)) {
            return session.components.arrayOf(game.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

/// Apply move and maybe change position of the screen
fn doMove(session: *game.GameSession, move: *game.Move, position: *game.Position, entity: game.Entity) void {
    const orig_point = position.point;
    const direction = move.direction.?;
    move.applyTo(position);

    if (entity != session.player) {
        return;
    }

    // keep player on the screen:
    const screen = &session.screen;
    const inner_region = screen.innerRegion();
    const dungeon = session.dungeon;
    const new_point = position.point;
    if (direction == .up and new_point.row < inner_region.top_left.row)
        screen.move(direction);
    if (direction == .down and new_point.row > inner_region.bottomRightRow())
        screen.move(direction);
    if (direction == .left and new_point.col < inner_region.top_left.col)
        screen.move(direction);
    if (direction == .right and new_point.col > inner_region.bottomRightCol())
        screen.move(direction);

    // maybe stop keep moving:
    var neighbors = dungeon.cellsAround(new_point) orelse return;
    while (neighbors.next()) |neighbor| {
        if (std.meta.eql(neighbors.cursor, orig_point))
            continue;
        if (std.meta.eql(neighbors.cursor, new_point))
            continue;
        switch (neighbor) {
            // keep moving
            .floor, .wall => {},
            // stop
            else => move.cancel(),
        }
    }
}
