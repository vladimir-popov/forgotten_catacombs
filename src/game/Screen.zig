const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Self = @This();

region: p.Region,

pub fn deinit(_: *@This()) void {}

pub fn centerAround(place: p.Point) Self {
    return .{
        .region = .{
            .top_left = .{
                .row = if (place.row > game.DISPLAY_ROWS / 2) place.row - game.DISPLAY_ROWS / 2 else 1,
                .col = if (place.col > game.DISPLAY_COLS / 2) place.col - game.DISPLAY_COLS / 2 else 1,
            },
            .rows = game.DISPLAY_ROWS,
            .cols = game.DISPLAY_COLS,
        },
    };
}
