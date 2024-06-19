const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const dung = @import("BspDungeon.zig");

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

pub const Components = union {
    position: Position,
    move: Move,
    sprite: Sprite,
    health: Health,
};
