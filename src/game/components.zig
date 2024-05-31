const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

pub const Dungeon = @import("Dungeon.zig").Dungeon(game.TOTAL_ROWS, game.TOTAL_COLS);

pub const Screen = @import("Screen.zig");

pub const Health = struct {
    health: u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Sprite = struct {
    position: p.Point,
    letter: []const u8,
    pub fn deinit(_: *@This()) void {}
};
