/// Set of methods to draw the game.
/// Comparing with `AnyRuntime`, this module contains methods
/// to draw objects from the game domain.
///
///   ╔═══════════════════════════════════════╗-------
///   ║                                       ║ |   |
///   ║                                       ║
///   ║                                       ║ S
///   ║                                       ║ c   D
///   ║                                       ║ r   i
///   ║                                       ║ e   s
///   ║                                       ║ e   p
///   ║                                       ║ n   l
///   ║                                       ║     a
///   ║                                       ║ |   y
///   ║═══════════════════════════════════════║---
///   ║HP: 100     Rat:||||||||||||||| Attack ║     |
///   ╚═══════════════════════════════════════╝-------
///   | Zone 0 |        Zone 1       | Zone 2 |
///   |             Stats            | Button |
const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const gm = @import("game.zig");

const OUT_ZONE_LENGTH = 8;
const MIDDLE_ZONE_LENGTH = gm.DISPLAY_COLS - (OUT_ZONE_LENGTH + 1) * 2;

const log = std.log.scoped(.render);

const Render = @This();

const DrawingMode = gm.AnyRuntime.DrawingMode;
const TextAlign = enum { center, left, right };

runtime: gm.AnyRuntime,
/// Visible area
screen: gm.Screen,

pub fn init(runtime: gm.AnyRuntime) Render {
    return .{
        .runtime = runtime,
        .screen = gm.Screen.init(gm.DISPLAY_ROWS - 1, gm.DISPLAY_COLS, gm.Dungeon.Region),
    };
}

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redraw(self: Render, session: *gm.GameSession, entity_in_focus: ?gm.Entity) !void {
    try self.runtime.clearDisplay();
    try self.runtime.drawUI();
    try self.drawScene(session, entity_in_focus);
}

/// Draws dungeon, sprites, animations, and stats on the screen.
/// Removes completed animations.
pub fn drawScene(self: Render, session: *gm.GameSession, entity_in_focus: ?gm.Entity) !void {
    // any runtime can have its own implementation of drawing the dungeon
    // in performance purposes
    try self.runtime.drawDungeon(&self.screen, session.level.dungeon);
    try self.drawSprites(session, entity_in_focus);
    try self.drawAnimationsFrame(session, entity_in_focus);
    try self.drawStats(session, entity_in_focus);
}

/// Draw sprites inside the screen and highlights the sprite of the entity in focus.
fn drawSprites(self: Render, session: *const gm.GameSession, entity_in_focus: ?gm.Entity) !void {
    var visible = std.PriorityQueue(ZOrderedSprites, void, compareZOrder).init(self.runtime.alloc, {});
    defer visible.deinit();

    var itr = session.level.query().get2(gm.Position, gm.Sprite);
    while (itr.next()) |tuple| {
        if (self.screen.region.containsPoint(tuple[1].point)) {
            try visible.add(tuple);
        }
    }
    while (visible.removeOrNull()) |tuple| {
        const mode: gm.AnyRuntime.DrawingMode = if (entity_in_focus == tuple[0])
            .inverted
        else
            .normal;
        try self.runtime.drawSprite(&self.screen, tuple[2], tuple[1], mode);
    }
}
const ZOrderedSprites = struct { gm.Entity, *gm.Position, *gm.Sprite };
fn compareZOrder(_: void, a: ZOrderedSprites, b: ZOrderedSprites) std.math.Order {
    if (a[2].z_order < b[2].z_order)
        return .lt
    else
        return .gt;
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
pub fn drawAnimationsFrame(self: Render, session: *gm.GameSession, entity_in_focus: ?gm.Entity) !void {
    const now: c_uint = self.runtime.currentMillis();
    var itr = session.level.query().get2(gm.Position, gm.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and self.screen.region.containsPoint(position.point)) {
                const mode: DrawingMode = if (entity_in_focus == components[0])
                    .inverted
                else
                    .normal;
                try self.runtime.drawSprite(
                    &self.screen,
                    &.{ .codepoint = frame },
                    position,
                    mode,
                );
            }
        } else {
            try session.level.components.removeFromEntity(components[0], gm.Animation);
        }
    }
}

/// Draws the hit points of the player, and the name and hit points of the entity in focus.
pub fn drawStats(self: Render, session: *const gm.GameSession, entity_in_focus: ?gm.Entity) !void {
    // Draw player's health, or pause mode indicator
    switch (session.mode) {
        .explore => try self.drawZone(0, "Pause", .normal, .center),
        .play => if (session.level.components.getForEntity(session.player, gm.Health)) |health| {
            var buf = [_]u8{0} ** 8;
            const text = try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current});
            try self.drawZone(0, text, .normal, .left);
        },
    }
    // Draw the name and health of the entity in focus
    if (entity_in_focus) |entity| {
        var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
        inline for (0..MIDDLE_ZONE_LENGTH) |i| buf[i] = ' ';
        var len: usize = 0;
        // Draw entity's name
        if (session.level.components.getForEntity(entity, gm.Description)) |desc| {
            len = (try std.fmt.bufPrint(&buf, "{s}", .{desc.name})).len;
        }
        // Draw enemy's health
        if (entity != session.player) {
            if (session.level.components.getForEntity(entity, gm.Health)) |health| {
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
        try self.drawZone(1, buf[0..len], .normal, .center);
    } else {
        try self.cleanZone(1);
    }
}

/// Draws quick action button, or hide it if quick_action is null.
pub fn drawQuickActionButton(self: Render, quick_action: ?gm.Action) !void {
    // Draw the quick action
    if (quick_action) |qa| {
        switch (qa.type) {
            .wait => try self.drawZone(2, "Wait", .inverted, .center),
            .open => try self.drawZone(2, "Open", .inverted, .center),
            .close => try self.drawZone(2, "Close", .inverted, .center),
            .hit => try self.drawZone(2, "Attack", .inverted, .center),
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => try self.drawZone(2, "Go up", .inverted, .center),
                .down => try self.drawZone(2, "Go down", .inverted, .center),
            },
            else => try self.cleanZone(2),
        }
    } else {
        try self.cleanZone(2);
    }
}

pub fn drawWelcomeScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    const middle = gm.DISPLAY_ROWS / 2 + 1;
    try self.drawText(gm.DISPLAY_COLS, "Welcome", .{ .row = middle - 1, .col = 1 }, .normal, .center);
    try self.drawText(gm.DISPLAY_COLS, "to", .{ .row = middle, .col = 1 }, .normal, .center);
    try self.drawText(gm.DISPLAY_COLS, "Forgotten catacomb", .{ .row = middle + 1, .col = 1 }, .normal, .center);
}

pub fn drawGameOverScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    try self.drawText(gm.DISPLAY_COLS, "You are dead", .{ .row = 1 + gm.DISPLAY_ROWS / 2, .col = 1 }, .normal, .center);
}

inline fn cleanZone(self: Render, comptime zone: u8) !void {
    try self.drawZone(zone, " ", .normal, .left);
}

inline fn drawZone(
    self: Render,
    comptime zone: u2,
    text: []const u8,
    mode: DrawingMode,
    aln: TextAlign,
) !void {
    switch (zone) {
        0 => try self.drawText(
            OUT_ZONE_LENGTH,
            text,
            .{ .row = gm.DISPLAY_ROWS, .col = 1 },
            mode,
            aln,
        ),
        1 => try self.drawText(
            MIDDLE_ZONE_LENGTH,
            text,
            .{ .row = gm.DISPLAY_ROWS, .col = OUT_ZONE_LENGTH + 1 },
            mode,
            aln,
        ),
        2 => try self.drawText(
            OUT_ZONE_LENGTH,
            text,
            .{ .row = gm.DISPLAY_ROWS, .col = gm.DISPLAY_COLS - OUT_ZONE_LENGTH },
            mode,
            aln,
        ),
        else => unreachable,
    }
}

fn drawText(
    self: Render,
    comptime len: u8,
    text: []const u8,
    absolut_position: p.Point,
    mode: gm.AnyRuntime.DrawingMode,
    aln: TextAlign,
) !void {
    var buf: [len]u8 = undefined;
    inline for (0..len) |i| buf[i] = ' ';
    const l = @min(len, text.len);
    switch (aln) {
        .left => std.mem.copyForwards(u8, &buf, text[0..l]),
        .center => std.mem.copyForwards(u8, buf[(len - l) / 2 ..], text[0..l]),
        .right => std.mem.copyForwards(u8, buf[(len - l)..], text[0..l]),
    }
    try self.runtime.drawText(&buf, absolut_position, mode);
}
