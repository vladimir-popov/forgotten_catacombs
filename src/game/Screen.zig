const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Self = @This();


/// The rows count to display
const DISPLAY_ROWS: u8 = 15;
/// The rows count to display
const DISPLAY_COLS: u8 = 40;

const ROWS_PAD = 3;
const COLS_PAD = 7;

region: p.Region,
dungeon_region: p.Region,

pub fn deinit(_: *@This()) void {}

pub fn centeredAround(point: p.Point, dungeon_region: p.Region) Self {
    return .{
        .region = .{
            .top_left = .{
                .row = if (point.row > DISPLAY_ROWS / 2) point.row - DISPLAY_ROWS / 2 else 1,
                .col = if (point.col > DISPLAY_COLS / 2) point.col - DISPLAY_COLS / 2 else 1,
            },
            .rows = DISPLAY_ROWS,
            .cols = DISPLAY_COLS,
        },
        .dungeon_region = dungeon_region,
    };
}

pub inline fn innerRegion(self: Self) p.Region {
    var inner_region = self.region;
    inner_region.top_left.row += ROWS_PAD;
    inner_region.top_left.col += COLS_PAD;
    inner_region.rows -= 2 * ROWS_PAD;
    inner_region.cols -= 2 * COLS_PAD;
    return inner_region;
}

pub fn move(self: *Self, direction: p.Direction) void {
    switch (direction) {
        .up => {
            if (self.region.top_left.row > 1)
                self.region.top_left.row -= 1;
        },
        .down => {
            if (self.region.bottomRight().row < self.dungeon_region.bottomRight().row)
                self.region.top_left.row += 1;
        },
        .left => {
            if (self.region.top_left.col > 1)
                self.region.top_left.col -= 1;
        },
        .right => {
            if (self.region.bottomRight().col < self.dungeon_region.bottomRight().col)
                self.region.top_left.col += 1;
        },
    }
}
