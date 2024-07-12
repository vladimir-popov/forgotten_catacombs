const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

const Self = @This();

previous_render_time: c_uint = 0,
// this lag is used to play animations
lag: u32 = 0,

pub fn render(self: *Self, session: *game.GameSession) anyerror!void {
    const now = session.runtime.currentMillis();
    self.lag += now - self.previous_render_time;
    self.previous_render_time = now;
    if (self.lag > game.RENDER_DELAY_MS) self.lag = 0;

    const screen = &session.screen;
    try session.runtime.clearScreen();
    // Draw UI
    try session.runtime.drawUI();
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
    // Draw animations
    for (session.components.getAll(game.Animation)) |*animation| {
        if (animation.frames.len > 0 and screen.region.containsPoint(animation.position)) {
            try session.runtime.drawSprite(
                screen,
                &.{ .codepoint = animation.frames[animation.frames.len - 1], .position = animation.position },
                .normal,
            );
            if (self.lag == 0)
                animation.frames.len -= 1;
        }
    }
    // Draw the right area (stats)
    if (session.components.getForEntity(session.player, game.Health)) |health| {
        var buf = [_]u8{0} ** game.STATS_COLS;
        try session.runtime.drawLabel(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current}),
            .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 2 },
        );
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
