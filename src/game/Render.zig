/// Set of methods to draw the game.
/// Comparing with `AnyRuntime`, this module contains methods
/// to draw objects from the game domain.
///
///   ╔═══════════════════════════════════════╗-------
///   ║                                       ║ |   |
///   ║                                       ║ V
///   ║                                       ║ i
///   ║                                       ║ e   D
///   ║                                       ║ w   i
///   ║                                       ║ p   s
///   ║                                       ║ o   p
///   ║                                       ║ r   l
///   ║                                       ║ t   a
///   ║                                       ║ |   y
///   ║═══════════════════════════════════════║---
///   ║HP: 100     Rat:||||||||||||||| Attack ║     |
///   ╚═══════════════════════════════════════╝-------
///   | Zone 0 |        Zone 1       | Zone 2 |
///   |             Stats            | Button |
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.render);

pub const DrawingMode = enum { normal, inverted };
pub const Visibility = enum { visible, known, invisible };
const TextAlign = enum { center, left, right };

const OUT_ZONE_LENGTH = 8;
const MIDDLE_ZONE_LENGTH = g.DISPLAY_COLS - (OUT_ZONE_LENGTH + 1) * 2 - 2;

const Render = @This();

/// Used to memorize drawn sprites to override sprites with lower z-index
arena: *std.heap.ArenaAllocator,
runtime: g.Runtime,
/// Custom function to decide should the place be drawn or not.
/// Usually provided by the Level, but the DungeonGenerator ha the different implementation
/// to make whole dungeon visible.
isVisible: *const fn (level: g.Level, place: p.Point) Visibility,

pub fn init(
    alloc: std.mem.Allocator,
    runtime: g.Runtime,
    is_visible: *const fn (level: g.Level, place: p.Point) Visibility,
) !Render {
    const arena = try alloc.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(alloc);
    return .{
        .arena = arena,
        .runtime = runtime,
        .isVisible = is_visible,
    };
}

pub fn deinit(self: *Render) void {
    const alloc = self.arena.child_allocator;
    self.arena.deinit();
    alloc.destroy(self.arena);
}

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redraw(self: Render, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
    try self.clearDisplay();
    // separate dung and stats:
    try self.drawHorizontalBorderLine(session.viewport.region.rows - 2, session.viewport.region.cols);
    try self.drawScene(session, entity_in_focus);
}

pub inline fn clearDisplay(self: Render) !void {
    try self.runtime.clearDisplay();
}

/// Draws dungeon, sprites, animations, and stats on the screen.
/// Removes completed animations.
pub fn drawScene(self: Render, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
    try self.drawDungeon(session.level, session.viewport);
    try self.drawSprites(session.level, session.viewport, entity_in_focus);
    try self.drawAnimationsFrame(session, entity_in_focus);
    try self.drawInfoBar(session, entity_in_focus);
}

pub fn drawDungeon(self: Render, level: g.Level, viewport: g.Viewport) anyerror!void {
    var itr = level.dungeon.cellsInRegion(viewport.region);
    var place = viewport.region.top_left;
    var sprite = c.Sprite{ .codepoint = undefined };
    while (itr.next()) |cell| {
        sprite.codepoint = switch (cell) {
            .floor => '.',
            .wall => '#',
            else => ' ',
        };
        try self.drawSprite(level, viewport, sprite, place, .normal);
        place.move(.right);
        if (!viewport.region.containsPoint(place)) {
            place.col = viewport.region.top_left.col;
            place.move(.down);
        }
    }
}

const ZOrderedSprites = struct { g.Entity, *c.Position, *c.Sprite };
fn compareZOrder(_: void, a: ZOrderedSprites, b: ZOrderedSprites) std.math.Order {
    if (a[2].z_order < b[2].z_order)
        return .lt
    else
        return .gt;
}
/// Draw sprites inside the screen and highlights the sprite of the entity in focus.
pub fn drawSprites(self: Render, level: g.Level, viewport: g.Viewport, entity_in_focus: ?g.Entity) !void {
    _ = self.arena.reset(.retain_capacity);
    var drawn = std.AutoHashMap(p.Point, c.Sprite).init(self.arena.allocator());

    var itr = level.query().get2(c.Position, c.Sprite);
    while (itr.next()) |tuple| {
        if (!viewport.region.containsPoint(tuple[1].point)) continue;

        var gop = try drawn.getOrPut(tuple[1].point);
        if (!gop.found_existing or gop.value_ptr.z_order < tuple[2].z_order) {
            gop.value_ptr = tuple[2];
        }
        const mode: g.Render.DrawingMode = if (entity_in_focus == tuple[0])
            .inverted
        else
            .normal;
        try self.drawSprite(level, viewport, gop.value_ptr.*, tuple[1].point, mode);
    }
}

fn drawSprite(
    self: Render,
    level: g.Level,
    viewport: g.Viewport,
    sprite: c.Sprite,
    place: p.Point,
    mode: g.Render.DrawingMode,
) anyerror!void {
    if (viewport.region.containsPoint(place)) {
        const position_on_display = p.Point{
            .row = place.row - viewport.region.top_left.row,
            .col = place.col - viewport.region.top_left.col,
        };
        switch (self.isVisible(level, place)) {
            .invisible => try self.runtime.drawSprite(' ', position_on_display, mode),
            .visible => try self.runtime.drawSprite(sprite.codepoint, position_on_display, mode),
            .known => {
                const codepoint: u21 = switch (sprite.codepoint) {
                    // always show this sprites
                    '#', ' ', '<', '>', '\'', '+' => sprite.codepoint,
                    // and others
                    else => '.',
                };
                try self.runtime.drawSprite(codepoint, position_on_display, mode);
            },
        }
    }
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
pub fn drawAnimationsFrame(self: Render, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
    const now: c_uint = self.runtime.currentMillis();
    var itr = session.level.query().get2(c.Position, c.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and session.viewport.region.containsPoint(position.point)) {
                const mode: DrawingMode = if (entity_in_focus == components[0])
                    .inverted
                else
                    .normal;
                try self.drawSprite(
                    session.level,
                    session.viewport,
                    .{ .codepoint = frame },
                    position.point,
                    mode,
                );
            }
        } else {
            try session.level.components.removeFromEntity(components[0], c.Animation);
        }
    }
}

/// Draws the hit points of the player, and the name and hit points of the entity in focus.
pub fn drawInfoBar(self: Render, session: *const g.GameSession, entity_in_focus: ?g.Entity) !void {
    // Draw player's health, or pause mode indicator
    switch (session.mode) {
        .explore => try self.drawZone(0, "Pause", .inverted),
        .play => if (session.level.components.getForEntity(session.level.player, c.Health)) |health| {
            var buf = [_]u8{0} ** 8;
            const text = try std.fmt.bufPrint(&buf, "HP: {d}", .{health.current});
            try self.drawZone(0, text, .normal);
        },
    }
    // Draw the name and health of the entity in focus
    if (entity_in_focus) |entity| {
        var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
        inline for (0..MIDDLE_ZONE_LENGTH) |i| buf[i] = ' ';
        var len: usize = 0;
        // Draw entity's name
        if (session.level.components.getForEntity(entity, c.Description)) |desc| {
            len = (try std.fmt.bufPrint(&buf, "{s}", .{desc.name})).len;
        }
        // Draw enemy's health
        if (entity != session.level.player) {
            if (session.level.components.getForEntity(entity, c.Health)) |health| {
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
        try self.drawZone(1, buf[0..len], .normal);
    } else {
        try self.cleanZone(1);
    }
}

fn drawHorizontalBorderLine(self: Render, row: u8, length: u8) !void {
    for (0..length) |col| {
        try self.runtime.drawSprite('═', .{ .row = row, .col = @intCast(col) }, .normal);
    }
}

/// Draws quick action button, or hide it if quick_action is null.
pub fn drawQuickActionButton(self: Render, quick_action: ?c.Action) !void {
    // Draw the quick action
    if (quick_action) |qa| {
        switch (qa.type) {
            .wait => try self.drawZone(2, "Wait", .inverted),
            .open => try self.drawZone(2, "Open", .inverted),
            .close => try self.drawZone(2, "Close", .inverted),
            .hit => try self.drawZone(2, "Attack", .inverted),
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => try self.drawZone(2, "Go up", .inverted),
                .down => try self.drawZone(2, "Go down", .inverted),
            },
            else => try self.cleanZone(2),
        }
    } else {
        try self.cleanZone(2);
    }
}

pub fn drawWelcomeScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    const vertical_middle = g.DISPLAY_ROWS / 2 - 1;
    try self.drawText(g.DISPLAY_COLS, "Welcome", .{ .row = vertical_middle - 1, .col = 1 }, .normal, .center);
    try self.drawText(g.DISPLAY_COLS, "to", .{ .row = vertical_middle, .col = 1 }, .normal, .center);
    try self.drawText(g.DISPLAY_COLS, "Forgotten catacombs", .{ .row = vertical_middle + 1, .col = 1 }, .normal, .center);
}

pub fn drawGameOverScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    try self.drawText(g.DISPLAY_COLS, "You are dead", .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = 1 }, .normal, .center);
}

inline fn cleanZone(self: Render, comptime zone: u8) !void {
    try self.drawZone(zone, " ", .normal);
}

inline fn drawZone(
    self: Render,
    comptime zone: u2,
    text: []const u8,
    mode: DrawingMode,
) !void {
    var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
    var pos = p.Point{ .row = g.DISPLAY_ROWS - 1, .col = 1 };
    const buf_len: u8 = switch (zone) {
        0 => OUT_ZONE_LENGTH,
        1 => blk: {
            pos.col = OUT_ZONE_LENGTH + 2;
            break :blk MIDDLE_ZONE_LENGTH;
        },
        2 => blk: {
            pos.col = g.DISPLAY_COLS - OUT_ZONE_LENGTH;
            break :blk OUT_ZONE_LENGTH;
        },
        else => unreachable,
    };
    if (buf_len > 0) {
        for (0..buf_len) |i| buf[i] = ' ';
        const pad: u8 = (buf_len - @min(text.len, buf_len)) / 2;
        std.mem.copyForwards(u8, buf[pad..], text);
        try self.drawText(buf_len, buf[0..buf_len], pos, mode, .left);
    }
}

fn drawText(
    self: Render,
    comptime max_length: u8,
    text: []const u8,
    absolut_position: p.Point,
    mode: g.Render.DrawingMode,
    aln: TextAlign,
) !void {
    const text_length = @min(max_length, text.len);
    var pos = absolut_position;
    switch (aln) {
        .left => {},
        .center => pos.col += (max_length - text_length) / 2,
        .right => pos.col += (max_length - text_length),
    }
    try self.runtime.drawText(text[0..text_length], pos, mode);
}
