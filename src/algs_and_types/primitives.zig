/// This module contains algorithms, data structures, and primitive types,
/// such as geometry primitives, enums, and other not domain value objects.
const std = @import("std");

pub const Side = enum {
    left,
    right,
    top,
    bottom,

    pub inline fn opposite(self: Side) Side {
        return switch (self) {
            .top => .bottom,
            .bottom => .top,
            .left => .right,
            .right => .left,
        };
    }

    pub inline fn isHorizontal(self: Side) bool {
        return self == .top or self == .bottom;
    }
};

/// The coordinates of a point. Index begins from 1.
pub const Point = struct {
    row: u8,
    col: u8,

    pub fn format(
        self: Point,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Point(r:{d}, c:{d})", .{ self.row, self.col });
    }

    pub fn movedTo(self: Point, direction: Side) Point {
        var point = self;
        point.move(direction);
        return point;
    }

    pub fn move(self: *Point, direction: Side) void {
        switch (direction) {
            .top => {
                if (self.row > 0) self.row -= 1;
            },
            .bottom => self.row += 1,
            .left => {
                if (self.col > 0) self.col -= 1;
            },
            .right => self.col += 1,
        }
    }
};

/// The region described as its top left corner
/// and count of rows and columns.
///
/// Example of the region 4x6:
///   c:1
/// r:1 *----*
///     |    |
///     |    |
///     *____* r:4
///        c:6
pub const Region = struct {
    /// Top left corner. Index of rows and cols begins from 1.
    top_left: Point,
    /// The count of rows in this region.
    rows: u8,
    /// The count of columns in this region.
    cols: u8,

    pub fn format(
        self: Region,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print(
            "Region(r:{d}, c:{d}, rows:{d}, cols:{d}, ratio:{d})",
            .{ self.top_left.row, self.top_left.col, self.rows, self.cols, self.ratio() },
        );
    }

    pub inline fn isHorizontal(self: Region) bool {
        return self.cols > self.rows;
    }

    /// rows / cols
    pub inline fn ratio(self: Region) f16 {
        const rows: f16 = @floatFromInt(self.rows);
        const cols: f16 = @floatFromInt(self.cols);
        return rows / cols;
    }

    pub inline fn bottomRight(self: Region) Point {
        return .{ .row = self.top_left.row + self.rows - 1, .col = self.top_left.col + self.cols - 1 };
    }

    /// Returns the area of this region.
    pub inline fn area(self: Region) u16 {
        return std.math.mulWide(u8, self.rows, self.cols);
    }

    pub fn scale(self: *Region, k: f16) void {
        const rows: f16 = @floatFromInt(self.rows);
        const cols: f16 = @floatFromInt(self.cols);
        self.rows = @intFromFloat(@round(rows * k));
        self.cols = @intFromFloat(@round(cols * k));
    }

    pub inline fn containsPoint(self: Region, point: Point) bool {
        return self.contains(point.row, point.col);
    }

    pub inline fn contains(self: Region, row: u8, col: u8) bool {
        return betweenInclusive(row, self.top_left.row, self.bottomRight().row) and
            betweenInclusive(col, self.top_left.col, self.bottomRight().col);
    }

    inline fn betweenInclusive(v: u8, l: u8, r: u8) bool {
        return l <= v and v <= r;
    }

    /// Returns true if the `other` region doesn't go beyond of this region.
    pub fn containsRegion(self: Region, other: Region) bool {
        if (self.top_left.row > other.top_left.row or self.top_left.col > other.top_left.col)
            return false;
        if (self.top_left.row + self.rows < other.top_left.row + other.rows)
            return false;
        if (self.top_left.col + self.cols < other.top_left.col + other.cols)
            return false;
        return true;
    }

    /// Splits vertically the region in two if it possible. The first one contains the top
    /// left corner and `cols` columns. The second has the other part.
    /// If splitting is impossible, returns null.
    /// ┌───┬───┐
    /// │ 1 │ 2 │
    /// └───┴───┘
    pub fn splitVertically(self: Region, cols: u8) ?struct { Region, Region } {
        if (0 < cols and cols < self.cols) {
            return .{
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col },
                    .rows = self.rows,
                    .cols = cols,
                },
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col + cols },
                    .rows = self.rows,
                    .cols = self.cols - cols,
                },
            };
        } else {
            return null;
        }
    }

    /// Splits horizontally the region in two if it possible. The first one contains the top
    /// left corner and `rows` rows. The second has the other part.
    /// If splitting is impossible, returns null.
    /// ┌───┐
    /// │ 1 │
    /// ├───┤
    /// │ 2 │
    /// └───┘
    pub fn splitHorizontally(self: Region, rows: u8) ?struct { Region, Region } {
        if (0 < rows and rows < self.rows) {
            return .{
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col },
                    .rows = rows,
                    .cols = self.cols,
                },
                Region{
                    .top_left = .{ .row = self.top_left.row + rows, .col = self.top_left.col },
                    .rows = self.rows - rows,
                    .cols = self.cols,
                },
            };
        } else {
            return null;
        }
    }

    /// Crops all rows before the `row` if it possible.
    ///
    /// ┌---┐
    /// ¦   ¦
    /// ├───┤ < row (exclusive)
    /// │ r │
    /// └───┘
    pub fn cropHorizontallyAfter(self: Region, row: u8) ?Region {
        if (self.top_left.row <= row and row < self.bottomRight().row) {
            // copy original:
            var region = self;
            region.top_left.row = row + 1;
            region.rows -= (row + 1 - self.top_left.row);
            return region;
        } else {
            return null;
        }
    }

    test cropHorizontallyAfter {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 3 };
        // when:
        const result = region.cropHorizontallyAfter(2);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 3, .col = 1 }, .rows = 3, .cols = 3 },
            result,
        );
    }

    /// Crops all cols before the `col` if it possible.
    ///
    /// ┌---┬───┐
    /// ¦   │ r │
    /// └---┴───┘
    ///     ^
    ///     col (exclusive)
    pub fn cropVerticallyAfter(self: Region, col: u8) ?Region {
        if (self.top_left.col <= col and col < self.bottomRight().col) {
            // copy original:
            var region = self;
            region.top_left.col = col + 1;
            region.cols -= (col + 1 - self.top_left.col);
            return region;
        } else {
            return null;
        }
    }

    test cropVerticallyAfter {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 };
        // when:
        const result = region.cropVerticallyAfter(2);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 1, .col = 3 }, .rows = 3, .cols = 3 },
            result,
        );
    }

    /// Crops all rows after the `row` (exclusive) if it possible.
    ///
    /// ┌───┐
    /// │ r │
    /// ├───┤ < row (exclusive)
    /// ¦   ¦
    /// └---┘
    pub fn cropHorizontallyTo(self: Region, row: u8) ?Region {
        if (self.top_left.row < row and row <= self.bottomRight().row) {
            // copy original:
            var region = self;
            region.rows = row - 1;
            return region;
        } else {
            return null;
        }
    }

    test cropHorizontallyTo {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 3 };
        // when:
        const result = region.cropHorizontallyTo(3);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 2, .cols = 3 },
            result,
        );
    }

    /// Crops all cols after the `col` (exclusive) if it possible.
    ///
    /// ┌───┬---┐
    /// │ r │   ¦
    /// └───┴---┘
    ///     ^
    ///     col (exclusive)
    pub fn cropVerticallyTo(self: Region, col: u8) ?Region {
        if (self.top_left.col < col and col <= self.bottomRight().col) {
            // copy original:
            var region = self;
            region.cols = col - 1;
            return region;
        } else {
            return null;
        }
    }

    test cropVerticallyTo {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 };
        // when:
        const result = region.cropVerticallyTo(3);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 2 },
            result,
        );
    }

    /// ┌───┐       ┌──────┐
    /// │  ┌───┐ => │      │
    /// └──│┘  │    │      │
    ///    └───┘    └──────┘
    pub fn unionWith(self: Region, other: Region) Region {
        return .{
            .top_left = .{
                .row = @min(self.top_left.row, other.top_left.row),
                .col = @min(self.top_left.col, other.top_left.col),
            },
            .rows = @max(self.rows, other.rows),
            .cols = @max(self.cols, other.cols),
        };
    }

    /// ┌───┐
    /// │  ┌───┐ =>    ┌┐
    /// └──│┘  │       └┘
    ///    └───┘
    pub fn intersect(self: Region, other: Region) ?Region {
        const top_left: Point = .{
            .row = @max(self.top_left.row, other.top_left.row),
            .col = @max(self.top_left.col, other.top_left.col),
        };
        const bottom_right: Point = .{
            .row = @min(self.bottomRight().row, other.bottomRight().row),
            .col = @min(self.bottomRight().col, other.bottomRight().col),
        };
        if (top_left.row < bottom_right.row and top_left.col < bottom_right.col) {
            return .{
                .top_left = top_left,
                .rows = bottom_right.row - top_left.row + 1,
                .cols = bottom_right.col - top_left.col + 1,
            };
        } else {
            return null;
        }
    }

    test "partial intersect" {
        // given:
        const x = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 5 };
        const y = Region{ .top_left = .{ .row = 3, .col = 3 }, .rows = 5, .cols = 5 };
        const expected = Region{ .top_left = .{ .row = 3, .col = 3 }, .rows = 3, .cols = 3 };
        // when:
        const actual1 = x.intersect(y);
        const actual2 = y.intersect(x);
        // then:
        try std.testing.expectEqualDeep(expected, actual1);
        try std.testing.expectEqualDeep(expected, actual2);
    }
    test "intersect with inner" {
        // given:
        const out = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 10, .cols = 10 };
        const inner = Region{ .top_left = .{ .row = 3, .col = 3 }, .rows = 5, .cols = 5 };
        // when:
        const actual1 = out.intersect(inner);
        const actual2 = inner.intersect(out);
        // then:
        try std.testing.expectEqualDeep(inner, actual1);
        try std.testing.expectEqualDeep(inner, actual2);
    }
};
