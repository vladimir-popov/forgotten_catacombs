const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

const Self = @This();

previous_render_time: c_uint = 0,
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
    // Highlight entity and draw quick action
    if (session.entity_in_focus) |target| {
        try highlightEntityInFocus(session, target.entity);
        if (target.quick_action) |qa|
            try drawQuickAction(session, qa);
    }
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
        if (session.state == .pause)
            try session.runtime.drawLabel("pause", .{ .row = 1, .col = game.DISPLAY_DUNG_COLS + 2 });
        var buf = [_]u8{0} ** game.STATS_COLS;
        try session.runtime.drawLabel(
            try std.fmt.bufPrint(&buf, "HP: {d}", .{health.hp}),
            .{ .row = 2, .col = game.DISPLAY_DUNG_COLS + 2 },
        );
    }
}

fn highlightEntityInFocus(session: *const game.GameSession, entity: game.Entity) !void {
    if (session.components.getForEntity(session.player, game.Sprite)) |player_sprite| {
        if (session.components.getForEntity(entity, game.Sprite)) |target_sprite| {
            if (!player_sprite.position.eql(target_sprite.position))
                try session.runtime.drawSprite(&session.screen, target_sprite, .inverted);
        }
    }
}

fn drawQuickAction(session: *const game.GameSession, quick_action: game.Action) !void {
    switch (quick_action) {
        .open => |door| if (session.components.getForEntity(door, game.Sprite)) |s| {
            try drawLabelAndHighlightQuickActionTarget(session, "Open", s);
        },
        .close => |door| if (session.components.getForEntity(door, game.Sprite)) |s| {
            try drawLabelAndHighlightQuickActionTarget(session, "Close", s);
        },
        .take => |_| {
            // try drawLabelAndHighlightQuickActionTarget(session, "Take");
        },
        .hit => |enemy| {
            // Draw details about the enemy:
            if (session.components.getForEntity(enemy, game.Sprite)) |sprite| {
                if (session.components.getForEntity(enemy, game.Health)) |hp| {
                    if (session.components.getForEntity(enemy, game.Description)) |desc| {
                        try drawLabelAndHighlightQuickActionTarget(session, "Attack", sprite);
                        try session.runtime.drawLabel(desc.name, .{
                            .row = 5,
                            .col = game.DISPLAY_DUNG_COLS + 2,
                        });
                        var buf: [2]u8 = undefined;
                        const len = std.fmt.formatIntBuf(&buf, hp.hp, 10, .lower, .{});
                        try session.runtime.drawLabel(buf[0..len], .{
                            .row = 6,
                            .col = game.DISPLAY_DUNG_COLS + 2,
                        });
                    }
                }
            }
        },
        else => {},
    }
}

inline fn drawLabelAndHighlightQuickActionTarget(
    session: *const game.GameSession,
    label: []const u8,
    sprite: *const game.Sprite,
) !void {
    const prompt_position = p.Point{ .row = game.DISPLPAY_ROWS, .col = game.DISPLAY_DUNG_COLS + 2 };
    try session.runtime.drawLabel(label, prompt_position);
    try session.runtime.drawSprite(&session.screen, sprite, .inverted);
}
