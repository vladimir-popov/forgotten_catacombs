const std = @import("std");
const g = @import("game");
const p = g.primitives;
const TestRuntime = @import("TestRuntime.zig");
const Inventory = @import("Inventory.zig");
const Player = @import("Player.zig");

const Self = @This();

arena: std.heap.ArenaAllocator,
runtime: TestRuntime,
render: g.Render,
session: g.GameSession,
player: Player,
tmp_dir: std.testing.TmpDir,

/// Creates a new game session with TestRuntime and the first level.
pub fn initEmpty(self: *Self) !void {
    self.tmp_dir = std.testing.tmpDir(.{});
    self.arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = self.arena.allocator();
    self.runtime = try TestRuntime.init(alloc, self.tmp_dir.dir);
    try self.render.init(alloc, self.runtime.runtime(), g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.session.initNew(alloc, 0, self.runtime.runtime(), self.render);
    self.player = .{ .test_session = self, .player = self.session.player };
}

pub fn deinit(self: *Self) void {
    self.tmp_dir.cleanup();
    self.arena.deinit();
}

pub fn tick(self: *Self) !void {
    try self.session.tick();
    self.runtime.display.merge(self.runtime.last_frame);
}

pub fn pressButton(self: *Self, button: g.Button.GameButton) !void {
    try self.runtime.pushed_buttons.append(self.arena.allocator(), .{ .game_button = button, .state = .released });
    try self.tick();
}

pub fn openInventory(self: *Self) !Inventory {
    try self.session.manageInventory();
    try self.tick();
    return .{ .test_session = self };
}
