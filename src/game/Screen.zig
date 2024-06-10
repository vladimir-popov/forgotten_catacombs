const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Self = @This();

/// the region which should be displayed
region: p.Region,
rows_pad: u8,
cols_pad: u8,
/// the dungeon region to keep the screen inside
dungeon_region: p.Region,

pub fn deinit(_: *@This()) void {}

pub fn init(rows: u8, cols: u8, dungeon_region: p.Region) Self {
    return .{
        .region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols },
        .rows_pad = @intFromFloat(@as(f16, @floatFromInt(rows)) * 0.2),
        .cols_pad = @intFromFloat(@as(f16, @floatFromInt(cols)) * 0.2),
        .dungeon_region = dungeon_region,
    };
}

pub fn centeredAround(self: *Self, point: p.Point) void {
    self.region.top_left = .{
        .row = if (point.row > self.region.rows / 2) point.row - self.region.rows / 2 else 1,
        .col = if (point.col > self.region.cols / 2) point.col - self.region.cols / 2 else 1,
    };
}

pub inline fn innerRegion(self: Self) p.Region {
    var inner_region = self.region;
    inner_region.top_left.row += self.rows_pad;
    inner_region.top_left.col += self.cols_pad;
    inner_region.rows -= 2 * self.rows_pad;
    inner_region.cols -= 2 * self.cols_pad;
    return inner_region;
}

pub fn move(self: *Self, direction: p.Direction) void {
    switch (direction) {
        .up => {
            if (self.region.top_left.row > 1)
                self.region.top_left.row -= 1;
        },
        .down => {
            if (self.region.bottomRightRow() < self.dungeon_region.bottomRightRow())
                self.region.top_left.row += 1;
        },
        .left => {
            if (self.region.top_left.col > 1)
                self.region.top_left.col -= 1;
        },
        .right => {
            if (self.region.bottomRightCol() < self.dungeon_region.bottomRightCol())
                self.region.top_left.col += 1;
        },
    }
}
