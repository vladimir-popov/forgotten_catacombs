const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.bit_map);

pub fn BitMap(comptime rows_count: u8, cols_count: u8) type {
    comptime {
        std.debug.assert(rows_count > 0);
        std.debug.assert(cols_count > 0);
    }
    return struct {
        pub const Error = error{
            WrongColumnsCountInString,
            WrongRowsCountInString,
        };

        const Self = @This();

        pub const rows: u8 = rows_count;
        pub const cols: u8 = cols_count;

        bitsets: []std.StaticBitSet(cols),

        pub fn initEmpty(alloc: std.mem.Allocator) !Self {
            var self: Self = .{ .bitsets = try alloc.alloc(std.StaticBitSet(cols), rows) };
            self.clear();
            return self;
        }

        pub fn initFull(alloc: std.mem.Allocator) !Self {
            var self: Self = .{ .bitsets = try alloc.alloc(std.StaticBitSet(cols), rows) };
            for (0..rows) |idx| {
                self.bitsets[idx] = std.StaticBitSet(cols).initFull();
            }
            return self;
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            alloc.free(self.bitsets);
            self.bitsets = undefined;
        }

        pub fn copyFrom(self: *BitMap(rows, cols), other: *const BitMap(rows, cols)) void {
            std.mem.copyForwards(std.StaticBitSet(cols), self.bitsets, other.bitsets);
        }

        pub fn clear(self: *Self) void {
            for (0..rows) |idx| {
                self.bitsets[idx] = std.StaticBitSet(cols).initEmpty();
            }
        }

        inline fn isOutside(row: u8, col: u8) bool {
            return (row == 0 or col == 0) or (row > rows or col > cols);
        }

        pub inline fn isOutside0(_: *Self, row_idx: usize, col_idx: usize) bool {
            return row_idx >= rows or col_idx >= cols;
        }

        pub fn parse(self: *Self, comptime symbol: u8, str: []const u8) !void {
            if (!@import("builtin").is_test) {
                @compileError("The function `parse` is for test purpose only");
            }
            var r: u8 = 1;
            var c: u8 = 1;
            for (str) |char| {
                switch (char) {
                    '\n' => {
                        if (c > cols + 1) {
                            log.err(
                                "Total columns count is {d}, but found {d} char '{c}' in the parsed string\n{s}\n",
                                .{ cols, c, char, str },
                            );
                            return Error.WrongColumnsCountInString;
                        }
                        r += 1;
                        c = 0;
                    },
                    symbol => {
                        self.set(r, c);
                    },
                    else => {
                        self.unset(r, c);
                    },
                }
                c += 1;
            }
        }

        pub inline fn isSet(self: Self, row: u8, col: u8) bool {
            if (isOutside(row, col)) return false;
            return self.bitsets[row - 1].isSet(col - 1);
        }

        pub inline fn isSet0(self: Self, row_idx: usize, col_idx: usize) bool {
            return self.bitsets[row_idx].isSet(col_idx);
        }

        pub inline fn set(self: *Self, row: u8, col: u8) void {
            if (isOutside(row, col)) return;
            self.bitsets[row - 1].set(col - 1);
        }

        pub inline fn set0(self: *Self, row_idx: usize, col_idx: usize) void {
            self.bitsets[row_idx].set(col_idx);
        }

        pub inline fn setAt(self: *Self, point: p.Point) void {
            self.set(point.row, point.col);
        }

        pub inline fn unset(self: *Self, row: u8, col: u8) void {
            if (isOutside(row, col)) return;
            self.bitsets[row - 1].unset(col - 1);
        }

        pub inline fn unset0(self: *Self, row_idx: usize, col_idx: usize) void {
            self.bitsets[row_idx].unset(col_idx);
        }

        pub inline fn unsetAt(self: *Self, point: p.Point) void {
            self.unset(point.row, point.col);
        }

        pub inline fn setRowValue(
            self: *Self,
            row: u8,
            from_col: u8,
            count: u8,
            value: bool,
        ) void {
            if (row == 0 or row >= rows) return;
            self.bitsets[row - 1].setRangeValue(
                .{ .start = from_col - 1, .end = from_col + count - 1 },
                value,
            );
        }

        pub fn setRegionValue(self: *Self, region: p.Region, value: bool) void {
            if (region.top_left.row > rows) {
                return;
            }
            if (region.top_left.col > cols) {
                return;
            }
            const to_row = @min(rows, region.bottomRightRow());
            const to_col = @min(cols, region.bottomRightCol());
            for (region.top_left.row - 1..to_row) |r0| {
                self.bitsets[r0].setRangeValue(
                    .{ .start = region.top_left.col - 1, .end = to_col },
                    value,
                );
            }
        }
    };
}

test "parse BitMap" {
    // given:
    const str =
        \\###
        \\# #
        \\###
    ;

    // when:
    var bitmap = try BitMap(3, 3).initEmpty(std.testing.allocator);
    defer bitmap.deinit(std.testing.allocator);
    try bitmap.parse('#', str);

    // then:
    for (0..3) |r| {
        for (0..3) |c| {
            const expected = !(r == 1 and c == 1);
            try std.testing.expectEqual(expected, bitmap.isSet(@intCast(r + 1), @intCast(c + 1)));
        }
    }
}

test "unset a region" {
    // given:
    var bitmap = try BitMap(10, 10).initFull(std.testing.allocator);
    defer bitmap.deinit(std.testing.allocator);
    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 5, .cols = 5 };

    // when:
    bitmap.setRegionValue(region, false);

    // then:
    for (bitmap.bitsets, 1..) |row, r| {
        for (0..10) |c_idx| {
            const cell = row.isSet(c_idx);
            const expect = !region.containsPoint(.{ .row = @intCast(r), .col = @intCast(c_idx + 1) });
            try std.testing.expectEqual(expect, cell);
        }
    }
}
