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

const Window = @This();

alloc: std.mem.Allocator,
title: [COLS]u8 = [1]u8{0} ** COLS,
/// The scrollable content of the window
lines: std.ArrayListUnmanaged(Line) = .empty,
/// How many scrolled lines should be skipped
scroll: usize = 0,
/// The index of the selected line
selected_line: ?usize = null,
tag: u8 = 0,

pub fn init(alloc: std.mem.Allocator) Window {
    std.log.debug("Init a window", .{});
    return .{
        .alloc = alloc,
        .scroll = 0,
        .title = [1]u8{0} ** COLS,
        .lines = .empty,
    };
}

pub fn deinit(self: *Window) void {
    self.lines.deinit(self.alloc);
}

/// Returns the region of the screen occupied by the window including border.
pub inline fn region(self: Window) p.Region {
    return .{
        .top_left = if (self.lines.items.len > g.Window.MAX_WINDOW_HEIGHT - 2)
            .{ .row = 1, .col = 2 }
        else
            .{ .row = @intCast(1 + (g.Window.MAX_WINDOW_HEIGHT - 2 - self.lines.items.len) / 2), .col = 2 },
        .rows = @intCast(self.visibleLines().len + 2),
        .cols = MAX_WINDOW_WIDTH,
    };
}

pub inline fn isScrolled(self: Window) bool {
    return self.lines.items.len > g.Window.MAX_WINDOW_HEIGHT - 2;
}

pub fn visibleLines(self: Window) [][g.Window.COLS]u8 {
    return if (self.isScrolled())
        self.lines.items[self.scroll .. self.scroll + g.Window.MAX_WINDOW_HEIGHT - 2]
    else
        self.lines.items;
}

pub fn addOneLine(self: *Window) !*Line {
    const line = try self.lines.addOne(self.alloc);
    line.* = [1]u8{' '} ** COLS;
    return line;
}

pub fn selectPreviousLine(self: *Window) void {
    if (self.selected_line) |selected_line| {
        if (selected_line > 0)
            self.selected_line = selected_line - 1
        else
            self.selected_line = self.lines.items.len - 1;
    }
}

pub fn selectNextLine(self: *Window) void {
    if (self.selected_line) |selected_line| {
        if (selected_line < self.lines.items.len - 1)
            self.selected_line = selected_line + 1
        else
            self.selected_line = 0;
    }
}
