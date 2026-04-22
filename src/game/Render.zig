//! This is a kind of the fat pointer similar to the `std.mem.Allocator`.
//! It means, the `Render` can be always passed by value.
//!
//! The `Render` provides methods to draw the game.
//! Comparing with `Runtime`, this module contains methods
//! to draw objects from the game domain.
//!
//! The Welcome and Game over screen, as windows are drawn directly to the
//! screen by Runtime methods.
//!
//! The game scene is drawing not directly to the screen, but to the buffer.
//! It makes it possible to calculate changed symbols and draw only them.
//!                                         HP
//!   ╔═══════════════════════════════════════╗-------
//!   ║                                     99║ |   |
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
//!   ║ Rat:|||||||||||||||    Info    Attack ║     | <- the InfoBar is not buffered
//!   ╚═══════════════════════════════════════╝-------
//!   |        Info         |Button B|Button A|
//!
const std = @import("std");
const g = @import("game_pkg.zig");
const cm = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.render);

pub const BUTTON_ZONE_LENGTH = 8;
pub const INFO_ZONE_LENGTH = g.DISPLAY_COLS - (BUTTON_ZONE_LENGTH + 1) * 2 - 2;

pub const Visibility = enum { visible, known, invisible };

// this should be used to erase a symbol
pub const default_filler = ' ';

const Self = @This();

runtime: g.Runtime,
/// A cache of the visible area.
scene_buffer: *SceneBuffer,

pub fn init(gpa: std.mem.Allocator, runtime: g.Runtime) !Self {
    return .{
        .runtime = runtime,
        .scene_buffer = try .create(gpa, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS),
    };
}

pub fn deinit(self: *Self) void {
    self.scene_buffer.destroy();
}

/// Draws the dungeon and visible sprites on the screen.
pub fn drawScene(self: *const Self, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
    const level = &session.level;
    try self.drawDungeonToBuffer(session.viewport, level);
    try self.drawEntitiesToBuffer(
        session.viewport,
        &session.journal,
        session.prng.random(),
        level,
        entity_in_focus,
        session.spent_turns,
    );
    try self.drawChangedSymbols();
}

pub fn fillRegion(self: *const Self, symbol: u21, mode: g.DrawingMode, region: p.Region) !void {
    var itr = region.cells();
    while (itr.next()) |cell| {
        try self.runtime.drawSprite(symbol, cell, mode);
    }
}

/// Clears both scene and info bar. Resets the inner buffer.
pub fn clearDisplay(self: *const Self) !void {
    self.scene_buffer.reset();
    try self.runtime.clearDisplay();
}

pub fn drawDungeonToBuffer(self: *const Self, viewport: g.Viewport, level: *g.Level) anyerror!void {
    var itr = level.dungeon.cellsInRegion(viewport.region);
    var place = viewport.region.top_left;
    while (itr.next()) |cell| {
        const visibility = level.checkPlaceVisibility(place);
        if (visibility == .visible and !level.isVisited(place))
            try level.addVisitedPlace(place);
        const codepoint = switch (cell) {
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
        try self.drawSpriteToBuffer(viewport, codepoint, place, 0, .normal, visibility);
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
/// Draws entities inside the screen to the render buffer
pub fn drawEntitiesToBuffer(
    self: *const Self,
    viewport: g.Viewport,
    journal: *g.Journal,
    /// Used to decide visibility of some objects
    rand: std.Random,
    level: *const g.Level,
    entity_in_focus: ?g.Entity,
    current_turn: u32,
) !void {
    var itr = level.registry.query2(cm.Position, cm.Sprite);
    while (itr.next()) |tuple| {
        const entity, const position, const sprite = tuple;
        if (!viewport.region.containsPoint(position.place)) continue;
        const mode: g.DrawingMode = if (entity.eql(entity_in_focus)) .inverted else .normal;
        const place_visibility = level.checkPlaceVisibility(position.place);
        const is_entity_visible = try g.visibility.isEntityVisibile(
            journal,
            rand,
            entity,
            sprite.codepoint,
            position.place,
            place_visibility,
            level.player,
            current_turn,
        );
        try self.drawSpriteToBuffer(
            viewport,
            if (is_entity_visible) sprite.codepoint else cp.floor_visible,
            position.place,
            @intFromEnum(position.zorder),
            mode,
            place_visibility,
        );
    }
}

pub fn drawSpriteToBuffer(
    self: *const Self,
    viewport: g.Viewport,
    codepoint: g.Codepoint,
    place_in_dungeon: p.Point,
    z_order: SceneBuffer.ZOrder,
    mode: g.DrawingMode,
    visibility: g.Render.Visibility,
) anyerror!void {
    const point_on_display = p.Point{
        .row = place_in_dungeon.row - viewport.region.top_left.row + 1,
        .col = place_in_dungeon.col - viewport.region.top_left.col + 1,
    };
    self.scene_buffer.setSymbol(
        point_on_display,
        actualCodepoint(codepoint, visibility),
        mode,
        z_order,
    );
}

/// This method validates visibility of the passed place, and
/// returns:
///  - the passed codepoint if the place is visible;
///  - the codepoint for invisible but known place;
///  - 'nothing' (space) if the place is invisible.
fn actualCodepoint(codepoint: g.Codepoint, visibility: g.Render.Visibility) g.Codepoint {
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
pub fn drawChangedSymbols(self: *const Self) !void {
    var itr = self.scene_buffer.changedSymbols();
    while (itr.next()) |tuple| {
        try self.runtime.drawSprite(tuple[1].codepoint, tuple[0], tuple[1].mode);
    }
}

/// Copies sprites from the scene buffer to the screen.
/// `region` - is a region inside the scene.
pub fn redrawRegionFromSceneBuffer(self: *const Self, region: p.Region) !void {
    var itr = region.cells();
    while (itr.next()) |point| {
        if (self.scene_buffer.getSymbol(point)) |symbol| {
            try self.runtime.drawSprite(symbol.codepoint, point, symbol.mode);
        }
    }
}

pub fn redrawFromSceneBuffer(self: *const Self) !void {
    try self.redrawRegionFromSceneBuffer(self.scene_buffer.region());
}

/// Draws a single symbol directly to display
pub fn drawSymbol(self: *const Self, symbol: u21, position_on_display: p.Point, mode: g.DrawingMode) !void {
    try self.runtime.drawSprite(symbol, position_on_display, mode);
}

/// Draws a one-line border of the region directly on the screen.
pub fn drawBorder(self: *const Self, region: p.Region) !void {
    var itr = region.cells();
    while (itr.next()) |point| {
        if (point.row == region.top_left.row or point.row == region.bottomRightRow()) {
            try self.runtime.drawSprite('─', point, .normal);
        } else if (point.col == region.top_left.col or point.col == region.bottomRightCol()) {
            try self.runtime.drawSprite('│', point, .normal);
        }
    }
    try self.runtime.drawSprite('┌', region.top_left, .normal);
    try self.runtime.drawSprite('└', region.bottomLeft(), .normal);
    try self.runtime.drawSprite('┐', region.topRight(), .normal);
    try self.runtime.drawSprite('┘', region.bottomRight(), .normal);
}

/// Draws a two-lines border of the region directly on the screen.
pub fn drawDoubledBorder(self: *const Self, region: p.Region, filler: ?u8) !void {
    var itr = region.cells();
    while (itr.next()) |point| {
        if (point.row == region.top_left.row or point.row == region.bottomRightRow()) {
            try self.runtime.drawSprite('═', point, .normal);
        } else if (point.col == region.top_left.col or point.col == region.bottomRightCol()) {
            try self.runtime.drawSprite('║', point, .normal);
        } else if (filler) |f| {
            try self.runtime.drawSprite(f, point, .normal);
        }
    }
    try self.runtime.drawSprite('╔', region.top_left, .normal);
    try self.runtime.drawSprite('╚', region.bottomLeft(), .normal);
    try self.runtime.drawSprite('╗', region.topRight(), .normal);
    try self.runtime.drawSprite('╝', region.bottomRight(), .normal);
}

pub fn drawHorizontalLine(self: *const Self, codepoint: u21, left_point: p.Point, length: u8) !void {
    var point = left_point;
    for (0..length) |_| {
        try self.runtime.drawSprite(codepoint, point, .normal);
        point.move(.right);
    }
}

// Draws the current count of player's hp at the top right corner
// directly on the screen.
pub fn drawPlayerHp(self: *const Self, health: *const cm.Health) !void {
    var buf = [_]u8{0} ** BUTTON_ZONE_LENGTH;
    const text = if (health.current_hp > 0)
        // hack to avoid showing '+'
        try std.fmt.bufPrint(&buf, "{d:2}", .{@abs(health.current_hp)})
    else
        try std.fmt.bufPrint(&buf, "{d:2}", .{health.current_hp});
    try self.drawText(text, .{ .row = 1, .col = g.DISPLAY_COLS - @as(u8, @intCast(text.len)) + 1 }, .inverted);
}

pub fn drawEnemyHealth(self: *const Self, codepoint: g.Codepoint, health: *const cm.Health) !void {
    var buf: [INFO_ZONE_LENGTH]u8 = undefined;
    inline for (0..INFO_ZONE_LENGTH) |i| buf[i] = default_filler;
    // +1 for padding between the right zone
    var len: u8 = try std.unicode.utf8Encode(codepoint, buf[1..]) + 1;

    buf[len] = ':';
    len += 1;
    const hp = @max(health.current_hp, 0);
    const free_length = INFO_ZONE_LENGTH - 3; // padding + codepoint (usually 1 byte for enemies) + ':'
    const hp_length = @divTrunc(free_length * hp, health.max);
    for (0..hp_length) |i| {
        buf[len + i] = '|';
    }
    len += free_length;
    try self.drawInfo(buf[0..len]);
}

/// Draws the text with center aligning in the Info field directly on the display.
/// The text should be no longer than `INFO_ZONE_LENGTH`.
/// All space except the text will be filled by the `filler`.
pub fn drawInfo(self: *const Self, text: []const u8) !void {
    const pos = p.Point{ .row = g.DISPLAY_ROWS, .col = 1 };
    try self.drawTextWithAlign(INFO_ZONE_LENGTH, text, pos, .normal, .center);
}

pub fn cleanInfo(self: *const Self) !void {
    var pos = p.Point{ .row = g.DISPLAY_ROWS, .col = 1 };
    for (0..INFO_ZONE_LENGTH) |_| {
        try self.drawSymbol(' ', pos, .normal);
        pos.move(.right);
    }
}

/// Draws the label for the B button
pub fn drawLeftButton(self: *const Self, text: []const u8, has_alternatives: bool) !void {
    var pos = p.Point{ .row = g.DISPLAY_ROWS, .col = INFO_ZONE_LENGTH + 1 };
    try self.runtime.drawSprite(
        if (has_alternatives) cp.variants else ' ',
        pos,
        .inverted,
    );
    pos.move(.right);
    try self.drawTextWithAlign(BUTTON_ZONE_LENGTH, text, pos, .inverted, .center);
}

pub fn hideLeftButton(self: *const Self) !void {
    var pos = p.Point{ .row = g.DISPLAY_ROWS, .col = INFO_ZONE_LENGTH + 1 };
    for (0..BUTTON_ZONE_LENGTH + 1) |_| {
        try self.drawSymbol(' ', pos, .normal);
        pos.move(.right);
    }
}

/// Draws the label for the A button
pub fn drawRightButton(self: *const Self, text: []const u8, has_alternatives: bool) !void {
    const pos = p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - BUTTON_ZONE_LENGTH };
    try self.drawTextWithAlign(BUTTON_ZONE_LENGTH, text, pos, .inverted, .center);
    try self.runtime.drawSprite(
        if (has_alternatives) cp.variants else ' ',
        .{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS },
        .inverted,
    );
}

pub fn hideRightButton(self: *const Self) !void {
    var pos = p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - BUTTON_ZONE_LENGTH };
    for (0..BUTTON_ZONE_LENGTH) |_| {
        try self.drawSymbol(' ', pos, .normal);
        pos.move(.right);
    }
}

/// Sets the line of spaces as a board on the passed side. Inverts the draw mode
/// for few symbols in the middle.
pub fn setBorderWithArrow(self: *const Self, viewport: g.Viewport, side: p.Direction) void {
    switch (side) {
        .left => self.scene_buffer.setSymbol(
            p.Point.point(1 + viewport.region.rows / 2, 1),
            '<',
            .inverted,
            std.math.maxInt(SceneBuffer.ZOrder),
        ),
        .right => self.scene_buffer.setSymbol(
            p.Point.point(1 + viewport.region.rows / 2, viewport.region.cols),
            '>',
            .inverted,
            std.math.maxInt(SceneBuffer.ZOrder),
        ),
        .up => self.scene_buffer.setSymbol(
            p.Point.point(1, viewport.region.cols / 2),
            '^',
            .inverted,
            std.math.maxInt(SceneBuffer.ZOrder),
        ),
        .down => self.scene_buffer.setSymbol(
            p.Point.point(viewport.region.rows, viewport.region.cols / 2),
            'v',
            .inverted,
            std.math.maxInt(SceneBuffer.ZOrder),
        ),
    }
}

/// Draws the passed text as utf8 encoded. Fills padding by the ' ' symbol to align the text
/// inside a zone with `zone_codepoints_max_count` width. If the text has more symbols, all extra
/// symbols will be cropped.
///
/// This method uses the `runtime.drawSprite()` to draw the text directly on the display avoiding
/// the scene buffer.
pub fn drawTextWithAlign(
    self: *const Self,
    zone_codepoints_max_count: usize,
    utf8_text: []const u8,
    absolut_position: p.Point,
    mode: g.DrawingMode,
    aln: g.TextAlign,
) !void {
    const text_length = @min(zone_codepoints_max_count, try std.unicode.utf8CountCodepoints(utf8_text));
    const left_pad = switch (aln) {
        .left => 0,
        .center => (zone_codepoints_max_count - text_length) / 2,
        .right => zone_codepoints_max_count - text_length,
    };
    const right_pad = zone_codepoints_max_count - text_length - left_pad;
    var cursor = absolut_position;
    for (0..left_pad) |_| {
        try self.drawSymbol(' ', cursor, mode);
        cursor.move(.right);
    }
    try self.drawTextWithMaxLength(utf8_text, text_length, cursor, mode);
    cursor.moveNTimes(.right, text_length);
    for (0..right_pad) |_| {
        try self.drawSymbol(' ', cursor, mode);
        cursor.move(.right);
    }
}

/// Draws the text directly on the screen without aligning and cropping.
pub fn drawText(self: *const Self, utf8_text: []const u8, position_on_display: p.Point, mode: g.DrawingMode) !void {
    try self.drawTextWithMaxLength(utf8_text, std.math.maxInt(usize), position_on_display, mode);
}

fn drawTextWithMaxLength(
    self: *const Self,
    utf8_text: []const u8,
    max_length: usize,
    position_on_display: p.Point,
    mode: g.DrawingMode,
) !void {
    var point = position_on_display;
    var lines: usize = 0;
    var itr = (try std.unicode.Utf8View.init(utf8_text)).iterator();
    while (itr.nextCodepoint()) |symbol| : (lines += 1) {
        if (lines >= max_length) break;

        try self.drawSymbol(symbol, point, mode);
        point.move(.right);
    }
}

pub fn drawTextToBuffer(
    self: *const Self,
    ascii_text: []const u8,
    position_on_display: p.Point,
    mode: g.DrawingMode,
) !void {
    var point = position_on_display;
    for (ascii_text) |symbol| {
        self.scene_buffer.setSymbol(point, symbol, mode, 3);
        point.move(.right);
    }
}

pub const DrawableSymbol = struct {
    codepoint: g.Codepoint,
    mode: g.DrawingMode,
};

const SceneBuffer = struct {
    pub const ZOrder = u3;

    const VersionedCell = struct {
        symbol: DrawableSymbol,
        z_order: ZOrder,
        ver: u1,
        is_changed: bool,
    };
    pub const Row = []VersionedCell;

    arena: std.heap.ArenaAllocator,
    rows: []Row,
    current_iteration: u1 = 1,

    pub fn create(gpa: std.mem.Allocator, rows: u8, cols: u8) !*SceneBuffer {
        const self = try gpa.create(SceneBuffer);
        self.arena = .init(gpa);
        const alloc = self.arena.allocator();
        self.rows = try alloc.alloc(Row, rows);
        for (0..rows) |r| {
            self.rows[r] = try alloc.alloc(VersionedCell, cols);
        }
        self.reset();
        return self;
    }

    pub fn destroy(self: *SceneBuffer) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self);
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

    pub fn region(self: SceneBuffer) p.Region {
        return p.Region.init(1, 1, @intCast(self.rows.len), @intCast(self.rows[0].len));
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
        z_order: ZOrder,
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
        var writer = std.Io.fixedBufferStream(&buf);
        self.write(writer.writer().any()) catch unreachable;
        log.debug("\n{s}", .{buf});
    }

    fn write(self: SceneBuffer, writer: std.Io.AnyWriter) !void {
        var buf: [4]u8 = undefined;
        for (self.rows) |row| {
            for (row) |cell| {
                if (!cell.is_changed) {
                    try writer.writeByte(default_filler);
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
