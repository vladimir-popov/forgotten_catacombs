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
//! ║                           Close Choose ║
//! ╚════════════════════════════════════════╝
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

// The size of the buffer in bytes for a single line
// with a small reserve for utf8 symbols
const COLS = g.DISPLAY_COLS + 5;

/// An array of bytes to store a label for an option.
/// It has slightly bigger length than `MAX_WIDTH` to be able to store a utf8 symbol.
pub const Line = [COLS]u8;

const Self = @This();

/// The scrollable content of the window
lines: std.ArrayListUnmanaged(Line) = .empty,

pub const empty: Self = .{};

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.lines.deinit(alloc);
}

pub fn totalLines(self: Self) usize {
    return self.lines.items.len;
}

pub fn button(_: Self) ?struct { []const u8, bool } {
    return null;
}

/// Adds a new line filled by ' '.
pub fn addEmptyLine(self: *Self, alloc: std.mem.Allocator) !*Line {
    const line = try self.lines.addOne(alloc);
    line.* = @splat(' ');
    return line;
}

/// Uses the render to draw the text area directly to the screen.
///
/// - `region` - A region of the screen to draw the content of the area.
///  The first symbol will be drawn at the top left corner of the region.
///
/// - `scrolled` - How many scrolled lines should be skipped.
pub fn draw(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) !void {
    log.debug("Drawing a text area inside {any}", .{region});
    var point = region.top_left;
    for (0..region.rows) |row_idx| {
        const line_idx = scrolled + row_idx;
        try render.drawTextWithAlign(region.cols, &self.lines.items[line_idx], point, .normal, .left);
        point.move(.down);
    }
}

/// true means that the button is recognized and handled
pub fn handleButton(_: *Self, _: g.Button) !void {}
