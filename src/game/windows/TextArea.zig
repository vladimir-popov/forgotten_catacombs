//! The simplest implementation of the `Area` interface. Contains a set of lines with a text
//! to draw in a window. Handles the right button to close the parent container.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;
const AllocatorError = std.mem.Allocator.Error;

const log = std.log.scoped(.windows);

// The size of the buffer in bytes for a single line
// with a small reserve for UTF-8 symbols.
const COLS = g.DISPLAY_COLS + 5;

const Self = @This();

/// A fixed-size buffer containing one line of text.
///
/// The buffer is slightly wider than the display so that a UTF-8 symbol near
/// the right edge does not require an additional allocation.
pub const Line = [COLS]u8;

alloc: std.mem.Allocator,
/// The text lines owned by this area.
lines: std.ArrayList(Line) = .empty,

/// Creates an empty text area using `alloc` for line storage.
pub fn initEmpty(alloc: std.mem.Allocator) Self {
    return .{ .alloc = alloc };
}

/// Releases the storage allocated for the text lines.
pub fn deinit(self: *Self) void {
    self.lines.deinit(self.alloc);
}

/// Returns the number of lines stored in the area.
pub fn totalLines(self: *const Self) usize {
    return self.lines.items.len;
}

/// Text areas do not have a selected line.
pub fn selectedLine(_: *const Self) ?usize {
    return null;
}

/// Returns the default buttons for a read-only text area.
///
/// The right button closes the parent window when pressed.
pub fn getButtons(_: *Self) w.Buttons {
    return .{ .right = .{ .label = "Close" } };
}

/// Handles input for the text area.
///
/// Pressing `a` requests that the parent window be closed. Other buttons do
/// not change the text area and keep the parent window open.
pub fn handleButton(_: *Self, btn: g.Button) w.HandleButtonResult {
    switch (btn.game_button) {
        .a => return .close_window,
        else => {},
    }
    return .keep_open;
}

/// Draws the visible part of the text area.
///
/// The area is cleared first. `scrolled` specifies the index of the first line
/// to draw, and at most `region.rows` lines are rendered. Text that exceeds the
/// available width is cropped by the renderer.
pub fn drawContent(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) (g.Runtime.Error || g.Utf8Error)!void {
    // Clear the region
    try render.fillRegion(g.Render.default_filler, .normal, region);
    // Draw the text
    var cursor = region.top_left.movedTo(.right);
    for (0..region.rows) |row_idx| {
        const line_idx = scrolled + row_idx;
        if (line_idx >= self.lines.items.len) break;
        try render.drawTextWithAlign(region.cols - 1, &self.lines.items[line_idx], cursor, .normal, .left);
        cursor.move(.down);
    }
}

/// Removes all lines while retaining the allocated capacity for reuse.
pub fn clearRetainingCapacity(self: *Self) void {
    self.lines.clearRetainingCapacity();
}

/// Appends a blank line and returns a pointer to its writable buffer.
pub fn addEmptyLine(self: *Self) AllocatorError!*Line {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    return line;
}

/// Appends a new line containing a copy of `text`.
///
/// The caller must ensure that `text` fits in a single line buffer.
pub fn printLine(self: *Self, text: []const u8) AllocatorError!void {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    @memcpy(line[0..text.len], text);
}

/// Formats and appends a new line using `fmt` and `args`.
pub fn printLineFmt(self: *Self, comptime fmt: []const u8, args: anytype) (AllocatorError || std.fmt.BufPrintError)!void {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    _ = try std.fmt.bufPrint(line, fmt, args);
}

/// Writes all stored lines to `writer`, one line per output line.
pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.lines.items) |line| {
        try writer.writeAll(&line);
        try writer.writeByte('\n');
    }
}
