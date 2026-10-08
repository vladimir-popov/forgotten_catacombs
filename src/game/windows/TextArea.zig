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

const Self = @This();

/// An array of bytes to store a label for an option.
/// It has slightly bigger length than `MAX_WIDTH` to be able to store a utf8 symbol.
pub const Line = [COLS]u8;

pub const ButtonWithHandler = struct {
    button: w.Button,
    context: *anyopaque,
    handler: *const fn (context: *anyopaque) anyerror!w.HandleButtonResult,
};

alloc: std.mem.Allocator,
/// The scrollable content of the window
lines: std.ArrayList(Line) = .empty,
b_button: ?ButtonWithHandler = null,
a_button: ?ButtonWithHandler = .{ .button = .close, .context = &.{}, .handler = closeHandler },

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

pub fn leftButton(self: *const Self) ?w.Button {
    if (self.b_button) |btn| {
        return btn.button;
    }
    return null;
}

pub fn rightButton(self: *const Self) ?w.Button {
    if (self.a_button) |btn| {
        return btn.button;
    }
    return null;
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    switch (btn.game_button) {
        .a => if (self.a_button) |button| {
            return try button.handler(button.context);
        },
        .b => if (self.b_button) |button| {
            return try button.handler(button.context);
        },
        else => {},
    }
    return .keep_open;
}

fn closeHandler(_: *anyopaque) !w.HandleButtonResult {
    return .close_window;
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

/// Creates a copy of the text as a new line.
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

pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
    for (self.lines.items) |line| {
        try writer.writeAll(&line);
        try writer.writeByte('\n');
    }
}
