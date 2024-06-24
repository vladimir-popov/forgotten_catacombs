const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.render);

pub fn render(session: *game.GameSession) anyerror!void {
    const screen = &session.screen;
    // Draw UI
    try session.runtime.drawUI();
    // Draw walls and floor
    try session.runtime.drawDungeon(screen, session.dungeon);
    // Draw quick actions list
    try drawQuickActionsList(session);
    // Draw sprites inside the screen
    for (session.components.getAll(game.Sprite)) |*sprite| {
        if (screen.region.containsPoint(sprite.position)) {
            try session.runtime.drawSprite(screen, sprite);
        }
    }
    // Draw animations
    for (session.components.getAll(game.Animation)) |*animation| {
        if (animation.frames.len > 0 and screen.region.containsPoint(animation.position)) {
            try session.runtime.drawSprite(
                screen,
                &.{ .codepoint = animation.frames[animation.frames.len - 1], .position = animation.position },
            );
            animation.frames.len -= 1;
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

fn drawQuickActionsList(session: *game.GameSession) !void {
    const prompt_position = p.Point{ .row = game.DISPLPAY_ROWS, .col = game.DISPLAY_DUNG_COLS + 3 };
    for (session.quick_actions.items) |action| {
        switch (action) {
            .open => try session.runtime.drawLabel("Open", prompt_position),
            .close => try session.runtime.drawLabel("Close", prompt_position),
            .take => |_| {
                try session.runtime.drawLabel("Take", prompt_position);
            },
            .hit => |enemy| {
                // Draw details about the enemy:
                if (session.components.getForEntity(enemy, game.Health)) |hp| {
                    if (session.components.getForEntity(enemy, game.Description)) |desc| {
                        try session.runtime.drawLabel("Attack", prompt_position);
                        try session.runtime.drawLabel(desc.name, .{
                            .row = 5,
                            .col = game.DISPLAY_DUNG_COLS + 3,
                        });
                        var buf: [2]u8 = undefined;
                        _ = std.fmt.formatIntBuf(&buf, hp.hp, 10, .lower, .{});
                        try session.runtime.drawLabel(&buf, .{
                            .row = 6,
                            .col = game.DISPLAY_DUNG_COLS + 3,
                        });
                    }
                }
            },
        }
    }
}

