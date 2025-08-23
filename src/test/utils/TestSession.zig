const std = @import("std");
const g = @import("game");
const p = g.primitives;
const TestRuntime = @import("TestRuntime.zig");

const Self = @This();

arena: std.heap.ArenaAllocator,
runtime: TestRuntime,
render: g.Render,
session: g.GameSession,

/// Creates a new game session with TestRuntime and the first level.
pub fn initEmpty(self: *Self, gpa: std.mem.Allocator, working_dir: std.fs.Dir) !void {
    self.arena = std.heap.ArenaAllocator.init(gpa);
    const alloc = self.arena.allocator();
    self.runtime = try TestRuntime.init(alloc, working_dir);
    try self.render.init(alloc, self.runtime.runtime(), g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.session.initNew(alloc, 0, self.runtime.runtime(), self.render);
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn tick(self: *Self) !void {
    try self.session.tick();
    self.runtime.display.merge(self.runtime.last_frame);
}
