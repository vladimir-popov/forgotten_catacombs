//! The simplest implementation of the `Area` interface. Contains a set of lines with a text
//! to draw in a window. Handles the right button to close the parent container.
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

alloc: std.mem.Allocator,
/// The scrollable content of the window
lines: std.ArrayList(Line) = .empty,

pub fn initEmpty(alloc: std.mem.Allocator) Self {
    return .{ .alloc = alloc };
}

pub fn deinit(self: *Self) void {
    self.lines.deinit(self.alloc);
}

pub fn area(self: *Self) w.Area {
    return .{ .underlying = self, .vtable = w.Area.vtableFor(Self) };
}

pub fn totalLines(self: *const Self) usize {
    return self.lines.items.len;
}

pub fn selectedLine(_: *const Self) ?usize {
    return null;
}

pub fn draw(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) !void {
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
    // Draw the button
    try render.hideLeftButton();
    try render.drawRightButton("Close", false);
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.lines.clearRetainingCapacity();
}

/// Adds a new line filled by ' '.
pub fn addEmptyLine(self: *Self) !*Line {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    return line;
}

pub fn printLine(self: *Self, text: []const u8) !void {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    @memcpy(line[0..text.len], text);
}

pub fn printLineFmt(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    const line = try self.lines.addOne(self.alloc);
    line.* = @splat(' ');
    _ = try std.fmt.bufPrint(line, fmt, args);
}

pub fn handleButton(_: *Self, btn: g.Button) !w.HandleButtonResult {
    return if (btn.game_button == .a) .close_window else .keep_open;
}

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.lines.items) |line| {
        try writer.writeAll(&line);
        try writer.writeByte('\n');
    }
}
