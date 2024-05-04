const std = @import("std");

pub const Region = struct {
    /// Top left corner row. Begins from 1.
    r: u8,
    /// Top left corner column. Begins from 1.
    c: u8,
    /// The count of rows in this region.
    rows: u8,
    /// The count of columns in this region.
    cols: u8,

    /// Returns true if this region has less rows or columns than passed minimal
    /// values.
    pub inline fn lessThan(self: Region, min_rows: u8, min_cols: u8) bool {
        return self.rows < min_rows or self.cols < min_cols;
    }

    /// Returns the area of this region.
    pub inline fn area(self: Region) u16 {
        return self.rows * self.cols;
    }

    /// Returns true if the `other` region doesn't go beyond of this region.
    pub fn contains(self: Region, other: Region) bool {
        if (self.r > other.r or self.c > other.c)
            return false;
        if (self.r + self.rows < other.r + other.rows)
            return false;
        if (self.c + self.cols < other.c + other.cols)
            return false;
        return true;
    }

    /// Splits this region vertically to two parts with no less than `min` columns in each.
    /// Returns null if splitting is impossible.
    pub fn splitVerticaly(self: Region, rand: std.Random, min: u8) ?struct { Region, Region } {
        if (split(rand, self.cols, min)) |middle| {
            return .{
                Region{ .r = self.r, .c = self.c, .rows = self.rows, .cols = middle },
                Region{ .r = self.r, .c = self.c + middle, .rows = self.rows, .cols = self.cols - middle },
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
                Region{ .r = self.r, .c = self.c, .rows = middle, .cols = self.cols },
                Region{ .r = self.r + middle, .c = self.c, .rows = self.rows - middle, .cols = self.cols },
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
};
