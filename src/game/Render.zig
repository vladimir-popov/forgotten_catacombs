/// Set of methods to draw the game.
/// Comparing with `AnyRuntime`, this module contains methods
/// to draw objects from the game domain.
///
///   ╔═══════════════════════════════════════╗
///   ║                                       ║
///   ║                                       ║
///   ║                                       ║
///   ║                                       ║
///   ║                                       ║
///   ║                  Screen               ║
///   ║                                       ║
///   ║                                       ║
///   ║                                       ║
///   ║                                       ║
///   ║═══════════════════════════════════════║
///   ║HP: 100     Wolf:||||||||||     Attack ║
///   ╚═══════════════════════════════════════╝
///   | Zone 0 |        Zone 1       | Zone 2 |
///
const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

const DrawingMode = game.AnyRuntime.DrawingMode;
const TextAlign = game.AnyRuntime.TextAlign;

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redraw(session: *game.GameSession) !void {
    try session.runtime.clearScreen();
    try session.runtime.drawUI();
    try drawScene(session);
}

/// Draws sprites and animations on the screen
pub fn drawScene(session: *game.GameSession) !void {
    // any runtime can have its own implementation of drawing the dungeon
    // in performance purposes
    try session.runtime.drawDungeon(&session.screen, session.dungeon);
    try drawSprites(session);
    try drawAnimationsFrame(session);
    try drawStats(session);
}

/// Draw sprites inside the screen ignoring lights
fn drawSprites(session: *const game.GameSession) !void {
    var itr = session.query.get2(game.Position, game.Sprite);
    while (itr.next()) |tuple| {
        if (session.screen.region.containsPoint(tuple[1].point)) {
            const mode: game.AnyRuntime.DrawingMode = if (session.entity_in_focus == tuple[0])
                .inverted
            else
                .normal;
            try session.runtime.drawSprite(&session.screen, tuple[2], tuple[1], mode);
        }
    }
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
fn drawAnimationsFrame(session: *game.GameSession) !void {
    const now: c_uint = session.runtime.currentMillis();
    var itr = session.query.get2(game.Position, game.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and session.screen.region.containsPoint(position.point)) {
                const mode: game.AnyRuntime.DrawingMode = if (session.entity_in_focus == components[0])
                    .inverted
                else
                    .normal;
                try session.runtime.drawSprite(
                    &session.screen,
                    &.{ .codepoint = frame },
                    position,
                    mode,
                );
            }
        } else {
            try session.components.removeFromEntity(components[0], game.Animation);
        }
    }
}

fn drawStats(session: *const game.GameSession) !void {
    // Draw player's health, or pause mode indicator
    switch (session.mode) {
        .pause => try drawZone(0, session, "Pause", .normal, .center),
        .play => if (session.components.getForEntity(session.player, game.Health)) |health| {
            var buf = [_]u8{0} ** 8;
            const text = try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current});
            try drawZone(0, session, text, .normal, .left);
        },
    }
    // Draw the name and health of the entity in focus
    if (session.entity_in_focus) |entity| {
        var buf: [game.DISPLAY_COLS - 18]u8 = undefined;
        var len: usize = 0;
        // Draw entity's name
        if (session.components.getForEntity(entity, game.Description)) |desc| {
            len = (try std.fmt.bufPrint(&buf, "{s}", .{desc.name})).len;
        }
        // Draw enemy's health
        if (entity != session.player) {
            if (session.components.getForEntity(entity, game.Health)) |hp| {
                buf[len] = ' ';
                len += 1;
                len += std.fmt.formatIntBuf(buf[len..], hp.current, 10, .lower, .{});
            }
        }
        try drawZone(1, session, buf[0..len], .normal, .center);
    } else {
        try cleanZone(1, session);
    }
    // Draw the quick action
    if (session.quick_action) |qa| {
        switch (qa.type) {
            .open => try drawZone(2, session, "Open", .inverted, .center),
            .close => try drawZone(2, session, "Close", .inverted, .center),
            .hit => try drawZone(2, session, "Attack", .inverted, .center),
            else => try cleanZone(2, session),
        }
    } else {
        try cleanZone(2, session);
    }
}

inline fn cleanZone(comptime zone: u8, session: *const game.GameSession) !void {
    try drawZone(zone, session, " ", .normal, .left);
}

inline fn drawZone(
    comptime zone: u2,
    session: *const game.GameSession,
    text: []const u8,
    mode: DrawingMode,
    aln: TextAlign,
) !void {
    switch (zone) {
        0 => try session.runtime.drawText(8, text, .{ .row = game.DISPLAY_ROWS, .col = 1 }, mode, aln),
        1 => try session.runtime.drawText(game.DISPLAY_COLS - 18, text, .{ .row = game.DISPLAY_ROWS, .col = 10 }, mode, aln),
        2 => try session.runtime.drawText(8, text, .{ .row = game.DISPLAY_ROWS, .col = game.DISPLAY_COLS - 8 }, mode, aln),
        else => unreachable,
    }
}
