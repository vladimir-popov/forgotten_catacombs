const std = @import("std");
const p = @import("primitives.zig");

const log = std.log.scoped(.walls);

const Walls = @This();

pub const Error = error{
    WrongColumnsCountInString,
    WrongRowsCountInString,
};

bitsets: std.ArrayList(std.DynamicBitSet),

pub fn initEmpty(alloc: std.mem.Allocator, rows: u8, cols: u8) !Walls {
    var bitsets = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
    for (0..rows) |_| {
        const row = bitsets.addOneAssumeCapacity();
        row.* = try std.DynamicBitSet.initEmpty(alloc, cols);
    }
    return .{ .bitsets = bitsets };
}

pub fn initFull(alloc: std.mem.Allocator, rows: u8, cols: u8) !Walls {
    var bitsets = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
    for (0..rows) |_| {
        const row = bitsets.addOneAssumeCapacity();
        row.* = try std.DynamicBitSet.initFull(alloc, cols);
    }
    return .{ .bitsets = bitsets };
}

pub fn deinit(self: Walls) void {
    for (self.bitsets.items) |*row| {
        row.deinit();
    }
    self.bitsets.deinit();
}

pub inline fn rowsCount(self: Walls) u8 {
    return @intCast(self.bitsets.items.len);
}

pub inline fn colsCount(self: Walls) u8 {
    return @intCast(self.bitsets.items[0].capacity());
}

pub fn parse(self: *Walls, str: []const u8) Error!void {
    var r: u8 = 1;
    var c: u8 = 1;
    for (str) |char| {
        switch (char) {
            '\n' => {
                if (c > self.colsCount() + 1) {
                    log.err(
                        "Total columns count is {d}, but found {d} char '{c}' in the parsed string\n{s}\n",
                        .{ self.colsCount(), c, char, str },
                    );
                    return Error.WrongColumnsCountInString;
                }
                r += 1;
                c = 0;
            },
            '#' => {
                self.setWall(r, c);
            },
            else => {
                self.removeWall(r, c);
            },
        }
        c += 1;
    }
    if (r < self.rowsCount()) {
        log.err(
            "Total rows count is {d}, but found {d} lines in the parsed string\n{s}\n",
            .{ self.rowsCount(), r, str },
        );
        return Error.WrongRowsCountInString;
    }
}

pub inline fn isWall(self: Walls, row: u8, col: u8) bool {
    return self.bitsets.items[row - 1].isSet(col - 1);
}

pub inline fn setWall(self: *Walls, row: u8, col: u8) void {
    self.bitsets.items[row - 1].set(col - 1);
}

pub inline fn setRowOfWalls(self: *Walls, row: u8, from_col: u8, count: u8) void {
    self.bitsets.items[row - 1].setRangeValue(.{ .start = from_col - 1, .end = from_col + count - 1 }, true);
}

pub inline fn removeWall(self: *Walls, row: u8, col: u8) void {
    self.bitsets.items[row - 1].unset(col - 1);
}

pub fn removeWalls(self: *Walls, region: p.Region) void {
    if (self.bitsets.items.len == 0 or region.top_left.row > self.bitsets.items.len) {
        return;
    }
    if (self.bitsets.items[0].capacity() == 0 or region.top_left.col > self.bitsets.items[0].capacity()) {
        return;
    }
    const to_row = @min(self.bitsets.items.len, region.bottomRight().row) + 1;
    const to_col = @min(self.bitsets.items[0].capacity(), region.bottomRight().col);
    for (region.top_left.row..to_row) |r| {
        self.bitsets.items[r - 1].setRangeValue(
            .{ .start = region.top_left.col - 1, .end = to_col },
            false,
        );
    }
}

test "parse walls" {
    // given:
    const str =
        \\###
        \\# #
        \\###
    ;
    var walls = try Walls.initEmpty(std.testing.allocator, 3, 3);
    defer walls.deinit();

    // when:
    try walls.parse(str);

    // then:
    for (0..3) |r| {
        for (0..3) |c| {
            const expected = !(r == 1 and c == 1);
            try std.testing.expectEqual(expected, walls.isWall(@intCast(r + 1), @intCast(c + 1)));
        }
    }
}

test "remove walls in the region" {
    // given:
    var walls = try Walls.initFull(std.testing.allocator, 10, 10);
    defer walls.deinit();
    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 5, .cols = 5 };

    // when:
    walls.removeWalls(region);

    // then:
    for (walls.bitsets.items, 1..) |walls_row, r| {
        for (0..walls_row.capacity()) |c_idx| {
            const cell = walls_row.isSet(c_idx);
            const expect = !region.contains(@intCast(r), @intCast(c_idx + 1));
            try std.testing.expectEqual(expect, cell);
        }
    }
}
