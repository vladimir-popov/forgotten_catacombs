const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const dung = @import("BspDungeon.zig");

pub const Dungeon = dung.BspDungeon(game.TOTAL_ROWS, game.TOTAL_COLS);

pub const Screen = @import("Screen.zig");

pub const Timers = struct {
    pub const Handlers = enum { input_system };

    alloc: std.mem.Allocator,
    timers: []i64,

    pub fn init(alloc: std.mem.Allocator) !Timers {
        return .{ .alloc = alloc, .timers = try alloc.alloc(i64, std.meta.tags(Handlers).len) };
    }
    pub fn deinit(self: *@This()) void {
        self.alloc.free(self.timers);
    }
};

pub const Level = struct {
    player: game.Entity,
    pub fn deinit(_: *@This()) void {}
};

pub const Position = struct {
    point: p.Point,
    pub fn deinit(_: *@This()) void {}
};

pub const Sprite = struct {
    letter: []const u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Move = struct {
    direction: ?p.Direction = null,
    keep_moving: bool = false,

    pub fn applyTo(self: *Move, position: *Position) void {
        if (self.direction) |direction| {
            position.point.move(direction);
        }
        if (!self.keep_moving)
            self.direction = null;
    }

    pub inline fn cancel(self: *Move) void {
        self.direction = null;
        self.keep_moving = false;
    }

    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    health: u8,
    pub fn deinit(_: *@This()) void {}
};
