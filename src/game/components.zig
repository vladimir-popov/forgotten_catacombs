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
    position: p.Point,
    pub fn deinit(_: *@This()) void {}
};

pub const Sprite = struct {
    letter: []const u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Move = struct {
    direction: ?p.Direction = null,
    speed: u8 = 1,

    pub fn doMove(self: Move, position: *p.Point) void {
        position.move(self.direction);
    }

    pub fn deinit(_: *@This()) void {}
};

pub const CollisionWithCell = struct {
    move: Move,
    cell: dung.Cell,
};

pub const Collision = union {
    with_cell: CollisionWithCell,
};

pub const Health = struct {
    health: u8,
    pub fn deinit(_: *@This()) void {}
};
