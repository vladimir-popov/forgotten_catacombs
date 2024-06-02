const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const dung = @import("Dungeon.zig");

pub const Dungeon = dung.Dungeon(game.TOTAL_ROWS, game.TOTAL_COLS);

pub const Screen = @import("Screen.zig");

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

    pub fn applyTo(self: *Move, position: *Position) void {
        if (self.direction) |direction| {
            position.point.move(direction);
        }
        self.direction = null;
    }

    pub inline fn ignore(self: *Move) void {
        self.direction = null;
    }

    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    health: u8,
    pub fn deinit(_: *@This()) void {}
};
