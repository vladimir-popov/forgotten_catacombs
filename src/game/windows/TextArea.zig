//! The area to draw a text with support of line highlighting,
//! adaptive vertical size, scrolling and optional border:
//! ╔════════════════════════════════════════╗
//! ║                                        ║
//! ║                                        ║
//! ║ ┌────────────────Title───────────────┐ ║
//! ║ │Arbitrary lines of a text           │ ║
//! ║ │with scroll and                     │ ║
//! ║ │optional░selection░░░░░░░░░░░░░░░░░░│ ║
//! ║ └────────────────────────────────────┘ ║
//! ║                                        ║
//! ║                                        ║
//! ║                                        ║
//! ║════════════════════════════════════════║
//! ║                                        ║
//! ╚════════════════════════════════════════╝
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

// The size of the buffer in bytes for a single line
// with a small reserve for utf8 symbols
pub const COLS = g.DISPLAY_COLS + 5;

/// An array of bytes to store a label for an option.
/// It has slightly bigger length than `MAX_WIDTH` to be able to store a utf8 symbol.
pub const Line = [COLS]u8;

/// Set of indexes of visible lines, which should be drawn inverted
pub const HighlightedLines = std.bit_set.IntegerBitSet(g.DISPLAY_ROWS);

pub const Options = struct {
    /// If true, then the `region` options should be interpret as a maximal, but not as an actually occupied region
    is_adaptive: bool = true,
    /// Actual or maximal occupied region (depends on `is_adaptive` option). This region includes a
    /// space for borders.
    region: p.Region,
    /// The mode to draw the border. If it's not specified then the border should not be drawn (but a
    /// place should be reserved).
    border: ?g.DrawingMode = null,

    pub const modal = Options{
        .border = .normal,
        .is_adaptive = true,
        .region = p.Region.init(1, 2, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS - 2),
    };

    pub const full_screen = Options{
        .border = null,
        .is_adaptive = false,
        .region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS), // -2 rows for infoBar
    };

    /// The maximum symbols in a row (few symbols can be reserved for border and/or scroll)
    pub fn maxLineSymbols(self: Options) u8 {
        // -2 for padding; -2 for borders; -1 for scroll.
        return self.region.cols - 5;
    }

    /// Returns the region that should be occupied (including border) according to the options and actual count of lines.
    pub fn actualRegion(self: Options, actual_rows: u8) p.Region {
        // Count of rows that should be drawn (including border)
        const rows: u8 = if (self.is_adaptive) actual_rows + 2 else self.region.rows; // 2 for border
        return .{
            .top_left = if (rows < self.region.rows)
                self.region.top_left.movedToNTimes(.down, (self.region.rows - rows) / 2)
            else
                self.region.top_left,
            .rows = @min(rows, self.region.rows),
            .cols = self.region.cols,
        };
    }
};

const TextArea = @This();

options: Options,
/// The scrollable content of the window
lines: std.ArrayListUnmanaged(Line) = .empty,
/// How many scrolled lines should be skipped
scroll: usize = 0,
highlighted_lines: HighlightedLines = .{ .mask = 0 },

pub fn init(draw_opts: Options) TextArea {
    return .{ .options = draw_opts };
}

pub fn deinit(self: *TextArea, alloc: std.mem.Allocator) void {
    self.lines.deinit(alloc);
}

pub inline fn isScrolled(self: TextArea) bool {
    return self.lines.items.len > self.options.region.rows - 2;
}

/// Returns slice of the visible lines only.
pub fn visibleLines(self: TextArea) [][COLS]u8 {
    return if (self.isScrolled())
        self.lines.items[self.scroll .. self.scroll + self.options.region.rows - 2]
    else
        self.lines.items;
}

/// Adds one item to the `lines`, and set array of spaces to it.
pub fn addEmptyLine(self: *TextArea, alloc: std.mem.Allocator, highlight: bool) !*Line {
    const line = try self.lines.addOne(alloc);
    line.* = @splat(' ');
    if (highlight)
        self.highlightLine(self.lines.items.len - 1);
    return line;
}

pub fn addLine(self: *TextArea, alloc: std.mem.Allocator, str: []const u8, highlight: bool) !void {
    const line = try self.addEmptyLine(alloc, highlight);
    _ = try std.fmt.bufPrint(line, "{s}", .{str});
}

pub fn highlightLine(self: *TextArea, absolute_line_idx: usize) void {
    std.debug.assert(absolute_line_idx < self.lines.items.len);
    const idx = absolute_line_idx - self.scroll;
    self.highlighted_lines.set(idx);
}

/// Turns off highlight from the line
pub fn unhighlightLine(self: *TextArea, absolute_line_idx: usize) void {
    std.debug.assert(absolute_line_idx < self.lines.items.len);
    const idx = absolute_line_idx - self.scroll;
    self.highlighted_lines.unset(idx);
}

/// Returns the region occupied by this area including borders.
pub fn region(self: *const TextArea) p.Region {
    return self.options.actualRegion(@intCast(self.visibleLines().len));
}

/// Uses the render to draw the text area directly to the screen.
pub fn draw(self: *const TextArea, render: g.Render) !void {
    const reg = self.region();
    var itr = reg.cells();
    while (itr.next()) |point| {
        if (point.row == reg.top_left.row or point.row == reg.bottomRightRow()) {
            if (self.options.border) |mode|
                try render.runtime.drawSprite('─', point, mode)
            else
                try render.runtime.drawSprite(' ', point, .normal);
        } else if (point.col == reg.top_left.col or point.col == reg.bottomRightCol()) {
            if (self.options.border) |mode|
                try render.runtime.drawSprite('│', point, mode)
            else
                try render.runtime.drawSprite(' ', point, .normal);
        } else {
            const row_idx = point.row - reg.top_left.row - 1;
            const abs_row_idx = row_idx + self.scroll;
            const col_idx = point.col - reg.top_left.col - 1;
            const mode: g.DrawingMode = if (self.highlighted_lines.isSet(row_idx)) .inverted else .normal;
            if (abs_row_idx < self.lines.items.len and col_idx < self.lines.items[abs_row_idx].len) {
                try render.runtime.drawSprite(self.lines.items[abs_row_idx][col_idx], point, mode);
            } else {
                try render.runtime.drawSprite(' ', point, mode);
            }
        }
    }
    //
    // Draw the corners
    //
    if (self.options.border) |mode| {
        try render.runtime.drawSprite('┌', reg.top_left, mode);
        try render.runtime.drawSprite('└', reg.bottomLeft(), mode);
        try render.runtime.drawSprite('┐', reg.topRight(), mode);
        try render.runtime.drawSprite('┘', reg.bottomRight(), mode);
    } else {
        try render.runtime.drawSprite(' ', reg.top_left, .normal);
        try render.runtime.drawSprite(' ', reg.bottomLeft(), .normal);
        try render.runtime.drawSprite(' ', reg.topRight(), .normal);
        try render.runtime.drawSprite(' ', reg.bottomRight(), .normal);
    }
}
