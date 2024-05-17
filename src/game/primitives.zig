/// This module contains primitive types, such as geometry primitives,
/// enums, and other not domain value objects.
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
};

/// The coordinates of a point. Index begins from 1.
pub const Point = struct {
    row: u8,
    col: u8,

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
/// r:1*----*
///    |    |
///    |    |
///    *____* r:4
///        c:6
pub const Region = struct {
    /// Top left corner. Index of rows and cols begins from 1.
    top_left: Point,
    /// The count of rows in this region.
    rows: u8,
    /// The count of columns in this region.
    cols: u8,

    pub inline fn isHorizontal(self: Region) bool {
        return self.cols > self.rows;
    }

    pub inline fn bottomRight(self: Region) Point {
        return .{ .row = self.top_left.row + self.rows - 1, .col = self.top_left.col + self.cols - 1 };
    }

    /// Returns true if this region has less rows or columns than passed minimal
    /// values.
    pub inline fn lessThan(self: Region, min_rows: u8, min_cols: u8) bool {
        return self.rows < min_rows or self.cols < min_cols;
    }

    /// Returns the area of this region.
    pub inline fn area(self: Region) u16 {
        return self.rows * self.cols;
    }

    pub inline fn containsPoint(self: Region, row: u8, col: u8) bool {
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

    /// Splits this region vertically to two parts with no less than `min` columns in each.
    /// Returns null if splitting is impossible.
    pub fn splitVerticaly(self: Region, rand: std.Random, min: u8) ?struct { Region, Region } {
        if (split(rand, self.cols, min)) |middle| {
            return .{
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col },
                    .rows = self.rows,
                    .cols = middle,
                },
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col + middle },
                    .rows = self.rows,
                    .cols = self.cols - middle,
                },
            };
        } else {
            return null;
        }
    }

    /// Splits this region horizontally to two parts with no less than `min` rows in each.
    /// Returns null if splitting is impossible.
    pub fn splitHorizontaly(self: Region, rand: std.Random, min: u8) ?struct { Region, Region } {
        if (split(rand, self.rows, min)) |middle| {
            return .{
                Region{
                    .top_left = .{ .row = self.top_left.row, .col = self.top_left.col },
                    .rows = middle,
                    .cols = self.cols,
                },
                Region{
                    .top_left = .{ .row = self.top_left.row + middle, .col = self.top_left.col },
                    .rows = self.rows - middle,
                    .cols = self.cols,
                },
            };
        } else {
            return null;
        }
    }

    /// Randomly splits the `value` to two parts which are not less than `min`,
    /// or return null if it is impossible.
    inline fn split(rand: std.Random, value: u8, min: u8) ?u8 {
        return if (value > min * 2)
            min + rand.uintLessThan(u8, value - min * 2)
        else if (value == 2 * min)
            min
        else
            null;
    }

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
};
