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
        try session.runtime.drawLabel(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current}),
            .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 2 },
        );
    }
    // Draw walls and floor
    try session.runtime.drawDungeon(screen, session.dungeon);
    // Draw sprites inside the screen
    for (session.components.getAll(game.Sprite)) |*sprite| {
        if (screen.region.containsPoint(sprite.position)) {
            try session.runtime.drawSprite(screen, sprite, .normal);
        }
    }
    // Draw mode's specifics
    try session.drawMode();
    // Draw a single frame from the every animation:
    try drawAnimationFrame(session, session.runtime.currentMillis());
}

fn drawAnimationFrame(session: *game.GameSession, now: c_uint) !void {
    var itr = session.query.get2(game.Sprite, game.Animation);
    while (itr.next()) |components| {
        const position = components[1].position;
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and session.screen.region.containsPoint(position)) {
                try session.runtime.drawSprite(
                    &session.screen,
                    &.{ .codepoint = frame, .position = position },
                    .normal,
                );
            }
        } else {
            try session.components.removeFromEntity(components[0], game.Animation);
        }
    }
}

pub fn drawEntityName(session: *const game.GameSession, name: []const u8) !void {
    try session.runtime.drawLabel(name, .{
        .row = 5,
        .col = game.DISPLAY_DUNG_COLS + 2,
    });
}

pub fn drawEnemyHP(session: *const game.GameSession, hp: *const game.Health) !void {
    var buf: [3]u8 = undefined;
    const len = std.fmt.formatIntBuf(&buf, hp.current, 10, .lower, .{});
    try session.runtime.drawLabel(buf[0..len], .{
        .row = 6,
        .col = game.DISPLAY_DUNG_COLS + 2,
    });
}
