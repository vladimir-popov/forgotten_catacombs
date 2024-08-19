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

const OUT_ZONE_LENGTH = 8;
const MIDDLE_ZONE_LENGTH = game.DISPLAY_COLS - (OUT_ZONE_LENGTH + 1) * 2;

const log = std.log.scoped(.render);

const DrawingMode = game.AnyRuntime.DrawingMode;
const TextAlign = game.AnyRuntime.TextAlign;

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redraw(session: *game.GameSession, entity_in_focus: ?game.Entity) !void {
    try session.runtime.clearScreen();
    try session.runtime.drawUI();
    try drawScene(session, entity_in_focus);
}

/// Draws dungeon, sprites, animations, and stats on the screen.
/// Removes completed animations.
pub fn drawScene(session: *game.GameSession, entity_in_focus: ?game.Entity) !void {
    // any runtime can have its own implementation of drawing the dungeon
    // in performance purposes
    try session.runtime.drawDungeon(&session.screen, session.dungeon);
    try drawSprites(session, entity_in_focus);
    try drawAnimationsFrame(session, entity_in_focus);
    try drawStats(session, entity_in_focus);
}

/// Draw sprites inside the screen and highlights the sprite of the entity in focus.
pub fn drawSprites(session: *const game.GameSession, entity_in_focus: ?game.Entity) !void {
    var visible = std.PriorityQueue(ZOrderedSprites, void, compareZOrder).init(session.runtime.alloc, {});
    defer visible.deinit();

    var itr = session.query.get2(game.Position, game.Sprite);
    while (itr.next()) |tuple| {
        if (session.screen.region.containsPoint(tuple[1].point)) {
            try visible.add(tuple);
        }
    }
    while (visible.removeOrNull()) |tuple| {
        const mode: game.AnyRuntime.DrawingMode = if (entity_in_focus == tuple[0])
            .inverted
        else
            .normal;
        try session.runtime.drawSprite(&session.screen, tuple[2], tuple[1], mode);
    }
}
const ZOrderedSprites = struct { game.Entity, *game.Position, *game.Sprite };
fn compareZOrder(_: void, a: ZOrderedSprites, b: ZOrderedSprites) std.math.Order {
    if (a[2].z_order < b[2].z_order)
        return .lt
    else
        return .gt;
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
pub fn drawAnimationsFrame(session: *game.GameSession, entity_in_focus: ?game.Entity) !void {
    const now: c_uint = session.runtime.currentMillis();
    var itr = session.query.get2(game.Position, game.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and session.screen.region.containsPoint(position.point)) {
                const mode: game.AnyRuntime.DrawingMode = if (entity_in_focus == components[0])
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

/// Draws the hit points of the player, and the name and hit points of the entity in focus.
pub fn drawStats(session: *const game.GameSession, entity_in_focus: ?game.Entity) !void {
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
    if (entity_in_focus) |entity| {
        var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
        inline for (0..MIDDLE_ZONE_LENGTH) |i| buf[i] = ' ';
        var len: usize = 0;
        // Draw entity's name
        if (session.components.getForEntity(entity, game.Description)) |desc| {
            len = (try std.fmt.bufPrint(&buf, "{s}", .{desc.name})).len;
            std.debug.assert(len < OUT_ZONE_LENGTH);
        }
        // Draw enemy's health
        if (entity != session.player) {
            if (session.components.getForEntity(entity, game.Health)) |health| {
                buf[len] = ':';
                len += 1;
                const hp = @max(health.current, 0);
                const free_length = MIDDLE_ZONE_LENGTH - len;
                const hp_length = @divFloor(free_length * hp, health.max);
                for (0..hp_length) |i| {
                    buf[len + i] = '|';
                }
                len += free_length;
            }
        }
        try drawZone(1, session, buf[0..len], .normal, .center);
    } else {
        try cleanZone(1, session);
    }
}

/// Draws quick action button, or hide it if quick_action is null.
pub fn drawQuickActionButton(session: *game.GameSession, quick_action: ?game.Action) !void {
    // Draw the quick action
    if (quick_action) |qa| {
        switch (qa.type) {
            .wait => try drawZone(2, session, "Wait", .inverted, .center),
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
        0 => try session.runtime.drawText(
            OUT_ZONE_LENGTH,
            text,
            .{ .row = game.DISPLAY_ROWS, .col = 1 },
            mode,
            aln,
        ),
        1 => try session.runtime.drawText(
            MIDDLE_ZONE_LENGTH,
            text,
            .{ .row = game.DISPLAY_ROWS, .col = OUT_ZONE_LENGTH + 1 },
            mode,
            aln,
        ),
        2 => try session.runtime.drawText(
            OUT_ZONE_LENGTH,
            text,
            .{ .row = game.DISPLAY_ROWS, .col = game.DISPLAY_COLS - OUT_ZONE_LENGTH },
            mode,
            aln,
        ),
        else => unreachable,
    }
}
