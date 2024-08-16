/// Set of methods to draw the game.
/// Comparing with `AnyRuntime`, this module contains methods
/// to draw objects from the game domain.
const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

/// The maximum length of any labels in the stats pane
const label_max_length = 8;

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
    // Draw player's health
    const player_hp_position = .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 2 };
    if (session.components.getForEntity(session.player, game.Health)) |health| {
        var buf = [_]u8{0} ** game.STATS_COLS;
        try session.runtime.drawText(
            label_max_length,
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current}),
            player_hp_position,
            .normal,
            .left,
        );
    }
    // Draw the name and health of the entity in focus
    const name_position = .{ .row = 5, .col = game.DISPLAY_DUNG_COLS + 2 };
    const enemy_hp_position = p.Point{ .row = 6, .col = game.DISPLAY_DUNG_COLS + 2 };
    if (session.entity_in_focus) |entity| {
        // Draw entity's name
        if (session.components.getForEntity(entity, game.Description)) |desc| {
            try session.runtime.drawText(label_max_length, desc.name, name_position, .normal, .center);
        }
        // Draw enemy's health
        if (entity != session.player) {
            if (session.components.getForEntity(entity, game.Health)) |hp| {
                var buf: [3]u8 = undefined;
                const len = std.fmt.formatIntBuf(&buf, hp.current, 10, .lower, .{});
                try session.runtime.drawText(label_max_length, buf[0..len], enemy_hp_position, .normal, .right);
            } else {
                try cleanLabel(session, enemy_hp_position);
            }
        } else {
            try cleanLabel(session, enemy_hp_position);
        }
    } else {
        try cleanLabel(session, name_position);
        try cleanLabel(session, enemy_hp_position);
    }
    // Draw the current mode
    const mode_position = .{ .row = 1, .col = game.DISPLAY_DUNG_COLS + 2 };
    switch (session.mode) {
        .pause => try session.runtime.drawText(label_max_length, "pause", mode_position, .normal, .center),
        .play => try cleanLabel(session, mode_position),
    }
    // Draw the quick action
    const prompt_position = p.Point{ .row = game.DISPLPAY_ROWS, .col = game.DISPLAY_DUNG_COLS + 2 };
    if (session.quick_action) |qa| {
        switch (qa.type) {
            .open => try session.runtime.drawText(label_max_length, "Open", prompt_position, .normal, .center),
            .close => try session.runtime.drawText(label_max_length, "Close", prompt_position, .normal, .center),
            .hit => try session.runtime.drawText(label_max_length, "Attack", prompt_position, .normal, .center),
            else => try cleanLabel(session, prompt_position),
        }
    } else {
        try cleanLabel(session, prompt_position);
    }
}

inline fn cleanLabel(session: *const game.GameSession, position: p.Point) !void {
    try session.runtime.drawText(label_max_length, " ", position, .normal, .left);
}
