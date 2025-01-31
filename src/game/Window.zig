const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

/// The maximum count of rows including borders needed to draw a window
pub const MAX_WINDOW_HEIGHT = g.DISPLAY_ROWS - 2;
/// The maximum count of columns including borders needed to draw a window
pub const MAX_WINDOW_WIDTH = g.DISPLAY_COLS - 2;

/// The max length of the visible content of the window
/// -2 for borders; -1 for scroll.
pub const COLS = MAX_WINDOW_WIDTH - 3;
const Line = [COLS]u8;

const Self = @This();

/// The scrollable content of the window
lines: std.ArrayList(Line),
title: [COLS]u8 = [1]u8{0} ** COLS,
scroll: u8 = 0,
selected_line: ?usize = null,
tag: u8 = 0,

pub fn init(alloc: std.mem.Allocator) !Self {
    return .{ .lines = std.ArrayList(Line).init(alloc) };
}

pub fn deinit(self: Self) void {
    self.lines.deinit();
}

pub fn addOneLine(self: *Self) !*Line {
    const line = try self.lines.addOne();
    line.* = [1]u8{' '} ** COLS;
    return line;
}

pub fn selectPrev(self: *Self) void {
    if (self.selected_line) |selected_line| {
        if (selected_line > 0)
            self.selected_line = selected_line - 1
        else
            self.selected_line = self.lines.items.len - 1;
    } else {
        self.selected_line = 0;
    }
}

pub fn selectNext(self: *Self) void {
    if (self.selected_line) |selected_line| {
        if (selected_line < self.lines.items.len - 1)
            self.selected_line = selected_line + 1
        else
            self.selected_line = 0;
    } else {
        self.selected_line = 0;
    }
}
