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

arena: *std.heap.ArenaAllocator,
title: [COLS]u8,
/// The scrollable content of the window
lines: std.ArrayList(Line),
scroll: u8,
selected_line: ?usize = null,
tag: u8 = 0,

pub fn create(alloc: std.mem.Allocator) !*Self {
    std.log.debug("Create a window", .{});
    const arena = try alloc.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(alloc);
    const self = try arena.allocator().create(Self);
    self.arena = arena;
    self.scroll = 0;
    self.title = [1]u8{0} ** COLS;
    self.lines = std.ArrayList(Line).init(arena.allocator());
    std.log.debug("The window was created", .{});
    return self;
}

pub fn destroy(self: Self) void {
    const alloc = self.arena.child_allocator;
    self.arena.deinit();
    alloc.destroy(self.arena);
}

pub fn addOneLine(self: *Self) !*Line {
    const line = try self.lines.addOne();
    line.* = [1]u8{' '} ** COLS;
    return line;
}
