/// Set of methods to draw the game.
/// Comparing with `Runtime`, this module contains methods
/// to draw objects from the game domain.
///
///   ╔═══════════════════════════════════════╗-------
///   ║                                       ║ |   |
///   ║                                       ║ V
///   ║                                       ║ i
///   ║                                       ║ e   D
///   ║             SceneBuffer               ║ w   i
///   ║                                       ║ p   s
///   ║                                       ║ o   p
///   ║                                       ║ r   l
///   ║                                       ║ t   a
///   ║                                       ║ |   y
///   ║═══════════════════════════════════════║---
///   ║HP: 100     Rat:||||||||||||||| Attack ║     | <- the InfoBar is not buffered
///   ╚═══════════════════════════════════════╝-------
///   | Zone 0 |        Zone 1       | Zone 2 |
///   |             Stats            |
///   |Button B|                     |Button A|
///
const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.render);

pub const DrawingMode = enum { normal, inverted };
pub const Visibility = enum { visible, known, invisible };
const TextAlign = enum { center, left, right };

const SIDE_ZONE_LENGTH = 8;
const MIDDLE_ZONE_LENGTH = g.DISPLAY_COLS - (SIDE_ZONE_LENGTH + 1) * 2 - 2;

// this should be used to erase a symbol
const filler = ' ';

const Render = @This();

pub const DrawableSymbol = struct {
    codepoint: g.Codepoint,
    mode: g.Render.DrawingMode,
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
    arena: *std.heap.ArenaAllocator,
    current_iteration: u1 = 1,

    pub fn init(alloc: std.mem.Allocator, rows: u8, cols: u8) !SceneBuffer {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        const arena_alloc = arena.allocator();
        var self = SceneBuffer{ .arena = arena, .rows = try arena_alloc.alloc(Row, rows) };
        for (0..rows) |r| {
            self.rows[r] = try arena_alloc.alloc(VersionedCell, cols);
        }
        self.reset();
        return self;
    }

    pub fn deinit(self: *SceneBuffer) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
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

    fn setSymbol(
        self: *SceneBuffer,
        point_in_buffer: p.Point,
        codepoint: g.Codepoint,
        mode: g.Render.DrawingMode,
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
        if (std.log.logEnabled(.debug, .viewport)) {
            // the biggest possible size of the viewport (in case when all codepoints < 255)
            var buf: [g.Dungeon.ROWS * (g.Dungeon.COLS + 1) + 1]u8 = undefined;
            var writer = std.io.fixedBufferStream(&buf);
            self.write(writer.writer().any()) catch unreachable;
            log.debug("\n{s}", .{buf});
        }
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

/// Usually provided by the Level, but the DungeonGenerator ha the different implementation
/// to make whole dungeon visible.
pub const VisibilityStrategy = struct {
    context: *anyopaque,
    /// Custom function to decide should the place be drawn or not.
    isVisible: *const fn (context: *anyopaque, place: p.Point) Visibility,
};

runtime: g.Runtime,
visibility_strategy: VisibilityStrategy,
/// Visible area
viewport: g.Viewport,
/// Cache for the visible area
buffer: SceneBuffer,

pub fn init(
    alloc: std.mem.Allocator,
    runtime: g.Runtime,
    visibility_strategy: VisibilityStrategy,
    scene_rows: u8,
    scene_cols: u8,
) !Render {
    return .{
        .runtime = runtime,
        .visibility_strategy = visibility_strategy,
        .viewport = try g.Viewport.init(scene_rows, scene_cols),
        .buffer = try SceneBuffer.init(alloc, scene_rows, scene_cols),
    };
}

pub fn deinit(self: *Render) void {
    self.buffer.deinit();
}

/// Draws dungeon, sprites, animations, and stats on the screen.
/// Removes completed animations.
pub fn drawScene(self: *Render, session: *g.GameSession, entity_in_focus: ?g.Entity, quick_action: ?g.Action) !void {
    try self.drawDungeon(session.level.dungeon);
    try self.drawSprites(session.level, entity_in_focus);
    try self.drawAnimationsFrame(session, entity_in_focus);
    try self.drawInfoBar(session, entity_in_focus, quick_action);
    try self.drawChangedSymbols();
}

// Should be used in DungeonGenerator only
pub fn drawLevelOnly(self: *Render, level: g.Level) !void {
    self.buffer.reset();
    try self.drawDungeon(level.dungeon);
    try self.drawSprites(level);
    try self.drawChangedSymbols();
}

/// Clears the screen and draw all from scratch.
/// Removes completed animations.
pub fn redraw(self: *Render, session: *g.GameSession, entity_in_focus: ?g.Entity, quick_action: ?g.Action) !void {
    try self.clearDisplay();
    self.buffer.reset();
    try self.drawScene(session, entity_in_focus, quick_action);
    try self.drawHorizontalBorderLine(self.viewport.region.rows + 1, self.viewport.region.cols);
}

/// Clears both scene and info bar.
pub inline fn clearDisplay(self: Render) !void {
    try self.runtime.clearDisplay();
}

fn drawDungeon(self: *Render, dungeon: g.Dungeon) anyerror!void {
    var itr = dungeon.cellsInRegion(self.viewport.region);
    var place = self.viewport.region.top_left;
    var sprite = c.Sprite{ .codepoint = undefined, .z_order = 0 };
    while (itr.next()) |cell| {
        sprite.codepoint = switch (cell) {
            .floor => cp.floor_visible,
            .wall => cp.wall_visible,
            else => cp.nothing,
        };
        try self.drawSprite(sprite, place, .normal);
        place.move(.right);
        if (!self.viewport.region.containsPoint(place)) {
            place.col = self.viewport.region.top_left.col;
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
/// Draw sprites inside the screen
fn drawSprites(self: *Render, level: g.Level, entity_in_focus: ?g.Entity) !void {
    var itr = level.query().get2(c.Position, c.Sprite);
    while (itr.next()) |tuple| {
        if (!self.viewport.region.containsPoint(tuple[1].point)) continue;
        const mode: g.Render.DrawingMode = if (tuple[0] == entity_in_focus) .inverted else .normal;
        try self.drawSprite(tuple[2].*, tuple[1].point, mode);
    }
}

fn drawSprite(
    self: *Render,
    sprite: c.Sprite,
    place_in_dungeon: p.Point,
    mode: g.Render.DrawingMode,
) anyerror!void {
    const point_on_display = p.Point{
        .row = place_in_dungeon.row - self.viewport.region.top_left.row + 1,
        .col = place_in_dungeon.col - self.viewport.region.top_left.col + 1,
    };
    const codepoint: g.Codepoint = self.actualCodepoint(sprite.codepoint, place_in_dungeon);
    self.buffer.setSymbol(point_on_display, codepoint, mode, sprite.z_order);
}

/// This method validates visibility of the passed place, and
/// return the passed codepoint if the place is visible, an  'nothing' if the place
/// invisible, or the codepoint for invisible but known place.
pub inline fn actualCodepoint(self: Render, codepoint: g.Codepoint, place: p.Point) g.Codepoint {
    return switch (self.visibility_strategy.isVisible(self.visibility_strategy.context, place)) {
        .visible => codepoint,
        .invisible => cp.nothing,
        .known => switch (codepoint) {
            // always show this known sprites
            cp.nothing, cp.ladder_up, cp.ladder_down, cp.door_opened, cp.door_closed => codepoint,
            cp.wall_visible => cp.wall_known,
            cp.floor_visible => cp.floor_known,
            else => cp.floor_known,
        },
    };
}

/// Invokes the runtime to draw only changed symbols.
/// After drawing all changes, the number of the viewport.buffer.iteration will be incremented.
fn drawChangedSymbols(self: *Render) !void {
    var itr = self.buffer.changedSymbols();
    while (itr.next()) |tuple| {
        try self.runtime.drawSprite(tuple[1].codepoint, tuple[0], tuple[1].mode);
    }
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
fn drawAnimationsFrame(self: *Render, session: *g.GameSession, entity_in_focus: ?g.Entity) !void {
    const now: c_uint = self.runtime.currentMillis();
    var itr = session.level.query().get2(c.Position, c.Animation);
    while (itr.next()) |components| {
        const position = components[1];
        const animation = components[2];
        if (animation.frame(now)) |frame| {
            if (frame > 0 and self.viewport.region.containsPoint(position.point)) {
                const mode: DrawingMode = if (entity_in_focus == components[0])
                    .inverted
                else
                    .normal;
                try self.drawSprite(
                    .{ .codepoint = frame, .z_order = 3 },
                    position.point,
                    mode,
                );
            }
        } else {
            try session.level.components.removeFromEntity(components[0], c.Animation);
        }
    }
}

fn drawHorizontalBorderLine(self: Render, row_on_display: u8, length: u8) !void {
    for (0..length) |col| {
        try self.runtime.drawSprite('═', .{ .row = row_on_display, .col = @intCast(col + 1) }, .normal);
    }
}

pub fn drawInfoBar(
    self: Render,
    session: *const g.GameSession,
    entity_in_focus: ?g.Entity,
    quick_action: ?g.Action,
) !void {
    try self.drawLeftZone(session);
    try self.drawMiddleZone(session, entity_in_focus);
    try self.drawRightZone(quick_action);
}

fn drawLeftZone(self: Render, session: *const g.GameSession) !void {
    switch (session.mode) {
        .explore => try self.drawZone(0, "Continue", .inverted),
        .play => if (session.level.components.getForEntity(session.level.player, c.Health)) |health| {
            var buf = [_]u8{0} ** 8;
            const text = try std.fmt.bufPrint(&buf, "HP:{d}", .{health.current});
            try self.drawZone(0, text, .normal);
        },
        .looking_around => try self.drawZone(0, "Cancel", .inverted),
    }
}

/// Draws quick action as the right button, or clear the right zone if the quick_action is null.
pub fn drawRightZone(self: Render, quick_action: ?g.Action) !void {
    // Draw the quick action
    if (quick_action) |qa| {
        switch (qa) {
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

fn drawMiddleZone(self: Render, session: *const g.GameSession, entity_in_focus: ?g.Entity) !void {
    switch (session.mode) {
        .looking_around => try self.drawZone(1, "Looking around", .normal),
        .play, .explore => {
            // Draw the name or health of the entity in focus
            if (entity_in_focus) |entity| {
                if (entity != session.level.player) {
                    if (session.level.components.getForEntity2(entity, c.Sprite, c.Health)) |tuple| {
                        try self.drawEnemyHealth(tuple[1].codepoint, tuple[2]);
                        return;
                    }
                }
                const name = if (session.level.components.getForEntity(entity, c.Description)) |desc| desc.name else "?";
                try self.drawZone(1, name, .normal);
            } else {
                try self.cleanZone(1);
            }
        },
    }
}

fn drawEnemyHealth(self: Render, codepoint: g.Codepoint, health: *const c.Health) !void {
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

/// Sets the line of spaces as a board on the passed side. Inverts the draw mode
/// for few symbols in the middle.
pub fn setBorderWithArrow(
    self: *Render,
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
            for (1..self.viewport.region.rows + 1) |r| {
                const is_middle = r == 1 + self.viewport.region.rows / 2;
                const codepoint: g.Codepoint = if (is_middle) arrow else filler;
                var point: p.Point = .{ .row = @intCast(r), .col = if (side == .left) 1 else self.viewport.region.cols };
                point.row = @intCast(r);
                self.buffer.setSymbol(point, codepoint, if (is_middle) .inverted else .normal, std.math.maxInt(g.ZOrder));
            }
        },
        .up, .down => {
            var point: p.Point = .{
                .row = if (side == .up) 1 else self.viewport.region.rows,
                .col = 1,
            };
            for (1..self.viewport.region.cols + 1) |cl| {
                const is_middle = (cl == self.viewport.region.cols / 2);
                const codepoint = if (is_middle) arrow else filler;
                point.col = @intCast(cl);
                self.buffer.setSymbol(point, codepoint, if (is_middle) .inverted else .normal, std.math.maxInt(g.ZOrder));
            }
        },
    }
}

pub fn drawWelcomeScreen(self: Render) !void {
    try self.clearDisplay();
    const vertical_middle = g.DISPLAY_ROWS / 2;
    try self.drawTextWithAlign(g.DISPLAY_COLS, "Welcome", .{ .row = vertical_middle - 1, .col = 1 }, .normal, .center);
    try self.drawTextWithAlign(g.DISPLAY_COLS, "to", .{ .row = vertical_middle, .col = 1 }, .normal, .center);
    try self.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Forgotten catacombs",
        .{ .row = vertical_middle + 1, .col = 1 },
        .normal,
        .center,
    );
}

pub fn drawGameOverScreen(self: Render) !void {
    try self.clearDisplay();
    try self.drawTextWithAlign(
        g.DISPLAY_COLS,
        "You are dead",
        .{ .row = g.DISPLAY_ROWS / 2, .col = 1 },
        .normal,
        .center,
    );
}

inline fn drawZone(
    self: Render,
    comptime zone: u2,
    text: []const u8,
    mode: DrawingMode,
) !void {
    const zone_len = if (zone == 1) MIDDLE_ZONE_LENGTH else SIDE_ZONE_LENGTH;
    const pos = switch (zone) {
        0 => p.Point{ .row = g.DISPLAY_ROWS, .col = 1 },
        1 => p.Point{ .row = g.DISPLAY_ROWS, .col = SIDE_ZONE_LENGTH + 1 },
        2 => p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - SIDE_ZONE_LENGTH + 1 },
        else => unreachable,
    };
    try self.drawTextWithAlign(zone_len, text, pos, mode, .center);
}

inline fn cleanZone(self: Render, comptime zone: u8) !void {
    const zone_len = if (zone == 1) MIDDLE_ZONE_LENGTH else SIDE_ZONE_LENGTH;
    const pos = switch (zone) {
        0 => p.Point{ .row = g.DISPLAY_ROWS, .col = 1 },
        1 => p.Point{ .row = g.DISPLAY_ROWS, .col = SIDE_ZONE_LENGTH + 1 },
        2 => p.Point{ .row = g.DISPLAY_ROWS, .col = g.DISPLAY_COLS - SIDE_ZONE_LENGTH + 1 },
        else => unreachable,
    };
    try self.drawTextWithAlign(zone_len, &.{filler}, pos, .normal, .left);
}

fn drawTextWithAlign(
    self: Render,
    comptime zone_length: u8,
    text: []const u8,
    absolut_position: p.Point,
    mode: g.Render.DrawingMode,
    aln: TextAlign,
) !void {
    var buf: [zone_length]u8 = undefined;
    inline for (0..zone_length) |i| buf[i] = filler;
    const text_length = @min(zone_length, text.len);
    const pad = switch (aln) {
        .left => 0,
        .center => (zone_length - text_length) / 2,
        .right => zone_length - text_length,
    };
    std.mem.copyForwards(u8, buf[pad..], text[0..text_length]);
    try self.runtime.drawText(&buf, absolut_position, mode);
}
