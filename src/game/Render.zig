//! Set of methods to draw the game.
//! Comparing with `Runtime`, this module contains methods
//! to draw objects from the game domain.
//!
//! The Welcome and Game over screen, as windows are drawn directly to the
//! screen by runtime methods.
//!
//! The game scene is drawing not directly to the screen, but to the buffer.
//! It makes it possible to calculate changed symbols and draw only them.
//!
//!   ╔═══════════════════════════════════════╗-------
//!   ║                                       ║ |   |
//!   ║                                       ║ V
//!   ║                                       ║ i
//!   ║                                       ║ e   D
//!   ║             SceneBuffer               ║ w   i
//!   ║                                       ║ p   s
//!   ║                                       ║ o   p
//!   ║                                       ║ r   l
//!   ║                                       ║ t   a
//!   ║                                       ║ |   y
//!   ║═══════════════════════════════════════║---
//!   ║HP: 100     Rat:||||||||||||||| Attack ║     | <- the InfoBar is not buffered
//!   ╚═══════════════════════════════════════╝-------
//!   | Zone 0 |        Zone 1       | Zone 2 |
//!   |Button B|                     |Button A|
//!
const std = @import("std");
const g = @import("game_pkg.zig");
const cm = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.render);

pub const Window = @import("Window.zig").Window;

pub const SIDE_ZONE_LENGTH = 8;
pub const MIDDLE_ZONE_LENGTH = g.DISPLAY_COLS - (SIDE_ZONE_LENGTH + 1) * 2 - 2;

pub const Visibility = enum { visible, known, invisible };

// this should be used to erase a symbol
const filler = ' ';

const Render = @This();

arena: std.heap.ArenaAllocator,
runtime: g.Runtime,
/// A pointer to the cache of the visible area.
scene_buffer: *SceneBuffer,
scene_rows: u8,
scene_cols: u8,

pub fn init(
    self: *Render,
    gpa: std.mem.Allocator,
    runtime: g.Runtime,
    scene_rows: u8,
    scene_cols: u8,
) !void {
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .runtime = runtime,
        .scene_buffer = try self.arena.allocator().create(SceneBuffer),
        .scene_rows = scene_rows,
        .scene_cols = scene_cols,
    };
    try self.scene_buffer.init(&self.arena, scene_rows, scene_cols);
}

pub fn deinit(self: *Render) void {
    self.arena.deinit();
}

pub fn drawWelcomeScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    const vertical_middle = g.DISPLAY_ROWS / 2;
    try self.runtime.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Welcome",
        .{ .row = vertical_middle - 1, .col = 1 },
        .normal,
        .center,
    );
    try self.runtime.drawTextWithAlign(
        g.DISPLAY_COLS,
        "to",
        .{ .row = vertical_middle, .col = 1 },
        .normal,
        .center,
    );
    try self.runtime.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Forgotten catacombs",
        .{ .row = vertical_middle + 1, .col = 1 },
        .normal,
        .center,
    );
}

pub fn drawGameOverScreen(self: Render) !void {
    try self.runtime.clearDisplay();
    try self.runtime.drawTextWithAlign(
        g.DISPLAY_COLS,
        "You are dead",
        .{ .row = g.DISPLAY_ROWS / 2, .col = 1 },
        .normal,
        .center,
    );
}

/// Draws dungeon, sprites, animations, and stats on the screen.
/// Removes completed animations.
pub fn drawScene(self: Render, session: *g.GameSession, entity_in_focus: ?g.Entity, quick_action: ?g.Action) !void {
    log.debug(
        "Draw scene of the level {d}; entity in focus {any}; quick action {any}",
        .{ session.level, entity_in_focus, quick_action },
    );
    log.debug("Draw dungeon", .{});
    try self.drawDungeon(session.viewport, &session.level);
    log.debug("Draw sprites", .{});
    try self.drawSpritesToBuffer(session.viewport, &session.level, entity_in_focus);
    log.debug("Draw animations", .{});
    try self.drawAnimationsFrame(session.viewport, &session.level, entity_in_focus);
    log.debug("Draw the horizontal line of the border", .{});
    try self.drawHorizontalBorderLine();
    log.debug("Draw changed symbols", .{});
    try self.drawChangedSymbols();
}

// Should be used in DungeonGenerator only
pub fn drawLevelOnly(self: *Render, viewport: g.Viewport, level: *g.Level) !void {
    self.scene_buffer.reset();
    try self.drawDungeon(viewport, level);
    try self.drawSpritesToBuffer(viewport, level, null);
    try self.drawChangedSymbols();
}

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redrawScene(self: *Render, session: *g.GameSession, entity_in_focus: ?g.Entity, quick_action: ?g.Action) !void {
    try self.clearDisplay();
    self.scene_buffer.reset();
    try self.drawScene(session, entity_in_focus, quick_action);
}

/// Clears both scene and info bar.
pub inline fn clearDisplay(self: Render) !void {
    try self.runtime.clearDisplay();
}

fn drawDungeon(self: Render, viewport: g.Viewport, level: *g.Level) anyerror!void {
    var itr = level.dungeon.cellsInRegion(viewport.region);
    var place = viewport.region.top_left;
    var sprite = cm.Sprite{ .codepoint = undefined, .z_order = 0 };
    while (itr.next()) |cell| {
        const visibility = level.checkVisibility(place);
        if (visibility == .visible and !level.map.isVisited(place))
            try level.map.addVisitedPlace(place);
        sprite.codepoint = switch (cell) {
            .nothing => cp.nothing,
            .floor => cp.floor_visible,
            .wall => cp.wall_visible,
            .rock => cp.rock,
            .water => cp.water,
            else => switch (@intFromEnum(cell)) {
                1...11 => cp.walls[@intFromEnum(cell) - 1],
                else => cp.unknown,
            },
        };
        try self.drawSpriteToBuffer(viewport, sprite, place, .normal, visibility);
        place.move(.right);
        if (!viewport.region.containsPoint(place)) {
            place.col = viewport.region.top_left.col;
            place.move(.down);
        }
    }
}

const ZOrderedSprites = struct { g.Entity, *cm.Position, *cm.Sprite };
fn compareZOrder(_: void, a: ZOrderedSprites, b: ZOrderedSprites) std.math.Order {
    if (a[2].z_order < b[2].z_order)
        return .lt
    else
        return .gt;
}
/// Draw sprites inside the screen
fn drawSpritesToBuffer(self: Render, viewport: g.Viewport, level: *const g.Level, entity_in_focus: ?g.Entity) !void {
    var itr = level.query().get2(cm.Position, cm.Sprite);
    while (itr.next()) |tuple| {
        if (!viewport.region.containsPoint(tuple[1].point)) continue;
        const mode: g.DrawingMode = if (tuple[0] == entity_in_focus) .inverted else .normal;
        const visibility = level.checkVisibility(tuple[1].point);
        try self.drawSpriteToBuffer(viewport, tuple[2].*, tuple[1].point, mode, visibility);
    }
}

fn drawSpriteToBuffer(
    self: Render,
    viewport: g.Viewport,
    sprite: cm.Sprite,
    place_in_dungeon: p.Point,
    mode: g.DrawingMode,
    visibility: g.Render.Visibility,
) anyerror!void {
    const point_on_display = p.Point{
        .row = place_in_dungeon.row - viewport.region.top_left.row + 1,
        .col = place_in_dungeon.col - viewport.region.top_left.col + 1,
    };
    self.scene_buffer.setSymbol(
        point_on_display,
        actualCodepoint(sprite.codepoint, visibility),
        mode,
        sprite.z_order,
    );
}

/// This method validates visibility of the passed place, and
/// return the passed codepoint if the place is visible, and  'nothing' if the place
/// invisible, or the codepoint for invisible but known place.
inline fn actualCodepoint(codepoint: g.Codepoint, visibility: g.Render.Visibility) g.Codepoint {
    return switch (visibility) {
        .visible => codepoint,
        .invisible => cp.nothing,
        .known => switch (codepoint) {
            cp.wall_visible => cp.wall_known,
            cp.floor_visible => cp.floor_known,
            cp.nothing, cp.ladder_up, cp.ladder_down, cp.door_opened, cp.door_closed => codepoint,
            cp.rock, cp.water, cp.teleport => codepoint,
            else => blk: {
                inline for (cp.walls) |w| {
                    if (w == codepoint) break :blk codepoint;
                }
                break :blk cp.floor_known;
            },
        },
    };
}

/// Invokes the runtime to draw only changed symbols.
/// After drawing all changes, the number of the viewport.buffer.iteration will be incremented.
fn drawChangedSymbols(self: Render) !void {
    var itr = self.scene_buffer.changedSymbols();
    while (itr.next()) |tuple| {
        try self.runtime.drawSprite(tuple[1].codepoint, tuple[0], tuple[1].mode);
    }
}

/// Uses the runtime to draw the window directly to the screen.
pub fn drawWindow(
    self: Render,
    window: *const g.Window,
) !void {
    const region = window.region();
    var itr = region.cells();
    while (itr.next()) |point| {
        if (point.row == region.top_left.row or point.row == region.bottomRightRow()) {
            try self.runtime.drawSprite('─', point, .normal);
        } else if (point.col == region.top_left.col or point.col == region.bottomRightCol()) {
            try self.runtime.drawSprite('│', point, .normal);
        } else {
            const row_idx = point.row - region.top_left.row - 1 + window.scroll;
            const col_idx = point.col - region.top_left.col - 1;
            const mode: g.DrawingMode = if (window.selected_line == row_idx) .inverted else .normal;
            if (row_idx < window.lines.items.len and col_idx < region.cols - 3) { // -3 for borders and scroll
                try self.runtime.drawSprite(window.lines.items[row_idx][col_idx], point, mode);
            } else {
                try self.runtime.drawSprite(' ', point, mode);
            }
        }
    }
    //
    // Draw the title
    //
    const title = std.mem.sliceTo(&window.title, 0);
    const padding: u8 = @intCast(region.cols - title.len);
    var point = region.top_left.movedToNTimes(.right, padding / 2);
    for (title) |char| {
        try self.runtime.drawSprite(char, point, .normal);
        point.move(.right);
    }
    //
    // Draw the corners
    //
    try self.runtime.drawSprite('┌', region.top_left, .normal);
    try self.runtime.drawSprite('└', region.top_left.movedToNTimes(.down, region.rows - 1), .normal);
    try self.runtime.drawSprite('┐', region.top_left.movedToNTimes(.right, region.cols - 1), .normal);
    try self.runtime.drawSprite(
        '┘',
        region.top_left.movedToNTimes(.down, region.rows - 1).movedToNTimes(.right, region.cols - 1),
        .normal,
    );
}

/// Copies sprites from the scene buffer to the screen.
/// `region` - is a region inside the scene.
pub fn redrawRegion(self: Render, region: p.Region) !void {
    var itr = region.cells();
    while (itr.next()) |point| {
        if (self.scene_buffer.getSymbol(point)) |symbol| {
            try self.runtime.drawSprite(symbol.codepoint, point, symbol.mode);
        }
    }
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
fn drawAnimationsFrame(self: Render, viewport: g.Viewport, level: *g.Level, entity_in_focus: ?g.Entity) !void {
    const now: c_uint = self.runtime.currentMillis();
    var itr = level.query().get2(cm.Position, cm.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and viewport.region.containsPoint(position.point)) {
                const mode: g.DrawingMode = if (entity_in_focus == components[0])
                    .inverted
                else
                    .normal;
                try self.drawSpriteToBuffer(
                    viewport,
                    .{ .codepoint = frame, .z_order = 3 },
                    position.point,
                    mode,
                    level.checkVisibility(position.point),
                );
            }
        } else {
            try level.components.removeFromEntity(components[0], cm.Animation);
        }
    }
}

fn drawHorizontalBorderLine(self: Render) !void {
    for (0..self.scene_cols) |col| {
        try self.runtime.drawSprite('═', .{ .row = self.scene_rows + 1, .col = @intCast(col + 1) }, .normal);
    }
}

pub inline fn drawLeftButton(self: Render, text: []const u8) !void {
    try self.drawZone(0, text, .inverted);
}

pub fn drawPlayerHp(self: Render, health: *const cm.Health) !void {
    var buf = [_]u8{0} ** SIDE_ZONE_LENGTH;
    const text = try std.fmt.bufPrint(&buf, "HP:{d}", .{health.current});
    try self.drawZone(0, text, .normal);
}

pub inline fn hideLeftButton(self: Render) !void {
    try self.cleanZone(0);
}

pub inline fn drawRightButton(self: Render, text: []const u8, has_alternatives: bool) !void {
    try self.drawZone(2, text, .inverted);
    if (has_alternatives) {
        const pos = p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS };
        try self.runtime.drawSprite(cp.variants, pos, .inverted);
    }
}

pub inline fn hideRightButton(self: Render) !void {
    try self.cleanZone(2);
}

pub inline fn drawInfo(self: Render, text: []const u8) !void {
    try self.drawZone(1, text, .normal);
}

pub fn drawEnemyHealth(self: Render, codepoint: g.Codepoint, health: *const cm.Health) !void {
    var buf: [MIDDLE_ZONE_LENGTH]u8 = undefined;
    inline for (0..MIDDLE_ZONE_LENGTH) |i| buf[i] = filler;
    // +1 for padding between the right zone
    var len: u8 = try std.unicode.utf8Encode(codepoint, buf[1..]) + 1;

    buf[len] = ':';
    len += 1;
    const hp = @max(health.current, 0);
    const free_length = MIDDLE_ZONE_LENGTH - 3; // padding + codepoint (usually 1 byte for enemies) + ':'
    const hp_length = @divFloor(free_length * hp, health.max);
    for (0..hp_length) |i| {
        buf[len + i] = '|';
    }
    len += free_length;
    try self.drawZone(1, buf[0..len], .normal);
}

pub inline fn cleanInfo(self: Render) !void {
    try self.cleanZone(1);
}

/// Sets the line of spaces as a board on the passed side. Inverts the draw mode
/// for few symbols in the middle.
pub fn setBorderWithArrow(
    self: Render,
    viewport: g.Viewport,
    side: p.Direction,
) void {
    const arrow: g.Codepoint = switch (side) {
        .up => '^',
        .down => 'v',
        .left => '<',
        .right => '>',
    };
    switch (side) {
        .left, .right => {
            for (1..self.scene_rows + 1) |r| {
                const is_middle = r == 1 + self.scene_rows / 2;
                const codepoint: g.Codepoint = if (is_middle) arrow else filler;
                var point: p.Point = .{ .row = @intCast(r), .col = if (side == .left) 1 else self.scene_cols };
                point.row = @intCast(r);
                self.scene_buffer.setSymbol(
                    point,
                    codepoint,
                    if (is_middle) .inverted else .normal,
                    std.math.maxInt(g.ZOrder),
                );
            }
        },
        .up, .down => {
            var point: p.Point = .{
                .row = if (side == .up) 1 else self.scene_rows,
                .col = 1,
            };
            for (1..self.scene_cols + 1) |cl| {
                const is_middle = (cl == viewport.region.cols / 2);
                const codepoint = if (is_middle) arrow else filler;
                point.col = @intCast(cl);
                self.scene_buffer.setSymbol(
                    point,
                    codepoint,
                    if (is_middle) .inverted else .normal,
                    std.math.maxInt(g.ZOrder),
                );
            }
        },
    }
}

inline fn drawZone(
    self: Render,
    comptime zone: u2,
    text: []const u8,
    mode: g.DrawingMode,
) !void {
    const zone_len = if (zone == 1) MIDDLE_ZONE_LENGTH - 2 else SIDE_ZONE_LENGTH;
    const pos = switch (zone) {
        0 => p.Point{ .row = g.DISPLAY_ROWS, .col = 1 },
        1 => p.Point{ .row = g.DISPLAY_ROWS, .col = SIDE_ZONE_LENGTH + 2 },
        2 => p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - SIDE_ZONE_LENGTH + 1 },
        else => unreachable,
    };
    try self.runtime.drawTextWithAlign(zone_len, text, pos, mode, .center);
}

inline fn cleanZone(self: Render, comptime zone: u8) !void {
    const zone_len = if (zone == 1) MIDDLE_ZONE_LENGTH else SIDE_ZONE_LENGTH;
    const pos = switch (zone) {
        0 => p.Point{ .row = g.DISPLAY_ROWS, .col = 1 },
        1 => p.Point{ .row = g.DISPLAY_ROWS, .col = SIDE_ZONE_LENGTH + 1 },
        2 => p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - SIDE_ZONE_LENGTH + 1 },
        else => unreachable,
    };
    try self.runtime.drawTextWithAlign(zone_len, &.{filler}, pos, .normal, .left);
}

pub const DrawableSymbol = struct {
    codepoint: g.Codepoint,
    mode: g.DrawingMode,
};

const SceneBuffer = struct {
    const VersionedCell = struct {
        symbol: DrawableSymbol,
        z_order: g.ZOrder,
        ver: u1,
        is_changed: bool,
    };
    pub const Row = []VersionedCell;

    rows: []Row,
    current_iteration: u1 = 1,

    pub fn init(self: *SceneBuffer, arena: *std.heap.ArenaAllocator, rows: u8, cols: u8) !void {
        const arena_alloc = arena.allocator();
        self.rows = try arena_alloc.alloc(Row, rows);
        for (0..rows) |r| {
            self.rows[r] = try arena_alloc.alloc(VersionedCell, cols);
        }
        self.reset();
    }

    pub fn reset(self: *SceneBuffer) void {
        self.current_iteration = 1;
        for (0..self.rows.len) |r| {
            for (self.rows[r]) |*cell| {
                cell.symbol.codepoint = 0;
                cell.z_order = 0;
                cell.ver = 0;
                cell.is_changed = false;
            }
        }
    }

    fn getSymbol(self: SceneBuffer, point: p.Point) ?DrawableSymbol {
        if (point.row > 0 and point.row <= self.rows.len) {
            if (point.col > 0 and point.col <= self.rows[0].len) {
                return self.rows[point.row - 1][point.col - 1].symbol;
            }
        }
        return null;
    }

    fn setSymbol(
        self: *SceneBuffer,
        point_in_buffer: p.Point,
        codepoint: g.Codepoint,
        mode: g.DrawingMode,
        z_order: g.ZOrder,
    ) void {
        std.debug.assert(point_in_buffer.row > 0);
        std.debug.assert(point_in_buffer.col > 0);
        std.debug.assert(point_in_buffer.row <= self.rows.len);
        std.debug.assert(point_in_buffer.col <= self.rows[0].len);

        const cell = &self.rows[point_in_buffer.row - 1][point_in_buffer.col - 1];
        defer cell.ver = self.current_iteration;

        if (cell.ver != self.current_iteration) {
            cell.is_changed = false;
        }

        // if the symbol is not changed from the previous iteration, the version
        // of the cell should not be changed
        if (cell.symbol.codepoint == codepoint and cell.symbol.mode == mode) return;

        // if the new symbol is under the existed at the same iteration, do nothing too
        if (cell.ver == self.current_iteration and cell.z_order > z_order) return;

        cell.symbol.codepoint = codepoint;
        // we should not override inverted mode at the same iteration
        // to prevent case when an entity out of focus but with bigger z-order
        // erases the backlight
        if (cell.symbol.mode != .inverted or cell.ver != self.current_iteration)
            cell.symbol.mode = mode;
        cell.z_order = z_order;
        cell.is_changed = true;
    }

    const CellIterator = struct {
        buffer: *SceneBuffer,
        r_idx: u8 = 0,
        c_idx: u8 = 0,

        pub fn next(self: *CellIterator) ?struct { p.Point, DrawableSymbol } {
            while (true) {
                defer self.c_idx += 1;

                if (self.c_idx == self.buffer.rows[0].len) {
                    self.r_idx += 1;
                    self.c_idx = 0;
                }
                if (self.r_idx == self.buffer.rows.len) {
                    self.buffer.current_iteration +%= 1;
                    return null;
                }

                const cell = &self.buffer.rows[self.r_idx][self.c_idx];
                if (cell.is_changed) {
                    return .{ .{ .row = self.r_idx + 1, .col = self.c_idx + 1 }, cell.symbol };
                }
            }
        }
    };

    fn changedSymbols(self: *SceneBuffer) CellIterator {
        // self.dumpToLog();
        return .{ .buffer = self };
    }

    fn dumpToLog(self: SceneBuffer) void {
        var buf: [10000]u8 = undefined;
        var writer = std.io.fixedBufferStream(&buf);
        self.write(writer.writer().any()) catch unreachable;
        log.debug("\n{s}", .{buf});
    }

    fn write(self: SceneBuffer, writer: std.io.AnyWriter) !void {
        var buf: [4]u8 = undefined;
        for (self.rows) |row| {
            for (row) |cell| {
                if (!cell.is_changed) {
                    try writer.writeByte(filler);
                    continue;
                }

                if (cell.symbol.codepoint < 255) {
                    try writer.writeByte(@intCast(cell.symbol.codepoint));
                } else {
                    const len = try std.unicode.utf8Encode(cell.symbol.codepoint, &buf);
                    _ = try writer.write(buf[0..len]);
                }
            }
            try writer.writeByte('\n');
        }
        try writer.writeByte(0);
    }
};
