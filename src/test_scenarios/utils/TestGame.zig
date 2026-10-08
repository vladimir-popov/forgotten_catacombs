const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const TestRuntime = @import("TestRuntime.zig");
const TickOptions = @import("TickOptions.zig");

const log = std.log.scoped(.test_game);

const Self = @This();

gpa: std.mem.Allocator,
runtime: TestRuntime,
tmp_dir: std.testing.TmpDir,
game: g.Game,

pub fn initWelcomeScreen(self: *Self, gpa: std.mem.Allocator, io: std.Io) !void {
    self.gpa = gpa;
    self.tmp_dir = std.testing.tmpDir(.{});
    self.runtime = try TestRuntime.init(gpa, io, self.tmp_dir.dir);
    self.game = try .init(gpa, self.runtime.runtime(), std.testing.random_seed);
    try self.tick(.{});
}

pub fn initNewCharacter(self: *Self, gpa: std.mem.Allocator, io: std.Io) !void {
    try self.initWelcomeScreen(gpa, io);
    try self.pressButton(.a);
}

pub fn deinit(self: *Self) void {
    self.tmp_dir.cleanup();
    self.runtime.deinit();
    self.game.deinit();
}

/// Creates a new empty last_frame buffer,
/// increase a clock on 1 second,
/// runs the method `session.tick(.{})`,
/// and merges the last_frame into the display buffer.
pub fn tick(self: *Self, opts: TickOptions) !void {
    for (0..opts.count) |_| {
        self.runtime.last_frame = .empty;
        self.runtime.current_millis += opts.duration_ms;
        try self.game.tick();
        self.runtime.display.merge(self.runtime.last_frame);
    }
}

pub fn pressButton(self: *Self, button: g.Button.GameButton) !void {
    log.debug("Emulate pressing button {any}", .{button});
    try self.runtime.pushed_buttons.append(self.gpa, .{ .game_button = button, .state = .released });
    try self.tick(.{ .duration_ms = 100 });
}
