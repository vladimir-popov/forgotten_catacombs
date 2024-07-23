const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

const Render = @This();

pub fn render(session: *game.GameSession) anyerror!void {
    const screen = &session.screen;
    try session.runtime.clearScreen();
    // Draw UI
    try session.runtime.drawUI();
    // Draw the right area (stats)
    if (session.components.getForEntity(session.player, game.Health)) |health| {
        var buf = [_]u8{0} ** game.STATS_COLS;
        try session.runtime.drawText(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current}),
            .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 2 },
        );
    }
    // Draw walls and floor
    try session.runtime.drawDungeon(screen, session.dungeon);
    // Draw sprites inside the screen
    var itr = session.query.get2(game.Position, game.Sprite);
    while (itr.next()) |tuple| {
        if (screen.region.containsPoint(tuple[1].point)) {
            try session.runtime.drawSprite(screen, tuple[2], tuple[1], .normal);
        }
    }
    // Draw mode's specifics
    try session.drawMode();
    // Draw a single frame from the every animation:
    try drawAnimationFrame(session, session.runtime.currentMillis());
}

fn drawAnimationFrame(session: *game.GameSession, now: c_uint) !void {
    var itr = session.query.get2(game.Position, game.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and session.screen.region.containsPoint(position.point)) {
                try session.runtime.drawSprite(
                    &session.screen,
                    &.{ .codepoint = frame },
                    position,
                    .normal,
                );
            }
        } else {
            try session.components.removeFromEntity(components[0], game.Animation);
        }
    }
}

pub fn drawEntityName(session: *const game.GameSession, name: []const u8) !void {
    try session.runtime.drawText(name, .{
        .row = 5,
        .col = game.DISPLAY_DUNG_COLS + 2,
    });
}

pub fn drawEnemyHP(session: *const game.GameSession, hp: *const game.Health) !void {
    var buf: [3]u8 = undefined;
    const len = std.fmt.formatIntBuf(&buf, hp.current, 10, .lower, .{});
    try session.runtime.drawText(buf[0..len], .{
        .row = 6,
        .col = game.DISPLAY_DUNG_COLS + 2,
    });
}
