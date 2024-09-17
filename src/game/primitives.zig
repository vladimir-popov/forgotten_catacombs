//! This module contains algorithms, data structures, and primitive types,
//! such as geometry primitives, which are not game domain objects.
const std = @import("std");

const log = std.log.scoped(.base);

pub const Direction = enum {
    left,
    right,
    up,
    down,

    pub inline fn opposite(self: Direction) Direction {
        return switch (self) {
            .up => .down,
            .down => .up,
            .left => .right,
            .right => .left,
        };
    }

    pub inline fn rotatedClockwise(self: Direction, is_clockwise: bool) Direction {
        const clockwise: Direction = switch (self) {
            .up => .right,
            .down => .left,
            .left => .up,
            .right => .down,
        };
        return if (is_clockwise) clockwise else clockwise.opposite();
    }

    pub inline fn isHorizontal(self: Direction) bool {
        return switch (self) {
            .right, .left => true,
            else => false,
        };
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

    pub inline fn move(self: *Point, direction: Direction) void {
        switch (direction) {
            .up => {
                if (self.row > 0) self.row -= 1;
            },
            .down => self.row += 1,
            .left => {
                if (self.col > 0) self.col -= 1;
            },
            .right => self.col += 1,
        }
    }

    pub fn movedTo(self: Point, direction: Direction) Point {
        var point = self;
        point.move(direction);
        return point;
    }

    pub inline fn moveNTimes(point: *Point, direction: Direction, n: u8) void {
        switch (direction) {
            .up => if (point.row >= n) {
                point.row -= n;
            },
            .down => if (point.row <= (255 - n)) {
                point.row += n;
            },
            .left => if (point.col >= n) {
                point.col -= n;
            },
            .right => if (point.col <= (255 - n)) {
                point.col += n;
            },
        }
    }

    pub fn movedToNTimes(self: Point, direction: Direction, n: u8) Point {
        var point = self;
        point.moveNTimes(direction, n);
        return point;
    }

    pub fn scaleCoordinates(self: *Point, v_scale: f16, h_scale: f16) void {
        self.row = @intFromFloat(@round(v_scale * @as(f16, @floatFromInt(self.row))));
        self.col = @intFromFloat(@round(h_scale * @as(f16, @floatFromInt(self.col))));
    }

    pub inline fn eql(self: Point, other: Point) bool {
        return self.row == other.row and self.col == other.col;
    }

    pub inline fn near(self: Point, other: Point) bool {
        return @max(self.row, other.row) - @min(self.row, other.row) < 2 and
            @max(self.col, other.col) - @min(self.col, other.col) < 2;
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

    pub fn validate(self: Region) void {
        if (@import("builtin").mode == .Debug) {
            const is_correct = self.top_left.row > 0 and
                self.top_left.col > 0 and
                self.rows > 0 and
                self.cols > 0 and
                256 > @as(u32, self.rows) + self.top_left.row and
                256 > @as(u32, self.cols) + self.top_left.col;
            if (!is_correct) {
                std.debug.panic("Incorrect {any}", .{self});
            }
        }
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

    pub inline fn bottomRightRow(self: Region) u8 {
        return self.top_left.row + self.rows - 1;
    }

    pub inline fn bottomRightCol(self: Region) u8 {
        return self.top_left.col + self.cols - 1;
    }

    /// Returns the area of this region.
    pub inline fn area(self: Region) u16 {
        return std.math.mulWide(u8, self.rows, self.cols);
    }

    pub inline fn middle(self: Region) Point {
        return .{ .row = self.top_left.row + self.rows / 2, .col = self.top_left.col + self.cols / 2 };
    }

    /// Multiplies rows by `v_scale` and columns by `h_scale`
    pub fn scale(self: *Region, v_scale: f16, h_scale: f16) void {
        const rows: f16 = @floatFromInt(self.rows);
        const cols: f16 = @floatFromInt(self.cols);
        self.rows = @intFromFloat(@round(rows * v_scale));
        self.cols = @intFromFloat(@round(cols * h_scale));
    }

    pub fn scaled(self: Region, v_scale: f16, h_scale: f16) Region {
        var reg = self;
        reg.scale(v_scale, h_scale);
        return reg;
    }

    pub inline fn containsPoint(self: Region, point: Point) bool {
        return self.top_left.row <= point.row and point.row <= self.bottomRightRow() and
            self.top_left.col <= point.col and point.col <= self.bottomRightCol();
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
        if (self.top_left.row <= row and row < self.bottomRightRow()) {
            // copy original:
            var region = self;
            region.top_left.row = row + 1;
            region.rows -= (row + 1 - self.top_left.row);
            self.validate();
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
        if (self.top_left.col <= col and col < self.bottomRightCol()) {
            // copy original:
            var region = self;
            region.top_left.col = col + 1;
            region.cols -= (col + 1 - self.top_left.col);
            self.validate();
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
        if (self.top_left.row < row and row <= self.bottomRightRow()) {
            // copy original:
            var region = self;
            region.rows = row - self.top_left.row;
            self.validate();
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
        if (self.top_left.col < col and col <= self.bottomRightCol()) {
            // copy original:
            var region = self;
            region.cols = col - self.top_left.col;
            self.validate();
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
        const top_left = .{
            .row = @min(self.top_left.row, other.top_left.row),
            .col = @min(self.top_left.col, other.top_left.col),
        };
        return .{
            .top_left = top_left,
            .rows = @max(self.bottomRightRow(), other.bottomRightRow()) - top_left.row + 1,
            .cols = @max(self.bottomRightCol(), other.bottomRightCol()) - top_left.col + 1,
        };
    }

    pub const CellsIterator = struct {
        region: Region,
        cursor: Point,

        pub fn next(self: *CellsIterator) ?Point {
            if (self.region.containsPoint(self.cursor)) {
                const cell = self.cursor;
                self.cursor.move(.right);
                if (self.cursor.col > self.region.bottomRightCol()) {
                    self.cursor.row += 1;
                    self.cursor.col = self.region.top_left.col;
                }
                return cell;
            } else {
                return null;
            }
        }
    };

    pub fn cells(self: Region) CellsIterator {
        return .{ .region = self, .cursor = self.top_left };
    }

    test "union with partial intersected" {
        // given:
        const x = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 5 };
        const y = Region{ .top_left = .{ .row = 3, .col = 3 }, .rows = 5, .cols = 5 };
        const expected = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 7, .cols = 7 };
        // when:
        const actual1 = x.unionWith(y);
        const actual2 = y.unionWith(x);
        // then:
        try std.testing.expectEqualDeep(expected, actual1);
        try std.testing.expectEqualDeep(expected, actual2);
    }
    test "union with inner region" {
        // given:
        const outer = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 10, .cols = 10 };
        const inner = Region{ .top_left = .{ .row = 3, .col = 3 }, .rows = 5, .cols = 5 };
        // when:
        const actual1 = outer.unionWith(inner);
        const actual2 = inner.unionWith(outer);
        // then:
        try std.testing.expectEqualDeep(outer, actual1);
        try std.testing.expectEqualDeep(outer, actual2);
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
            .row = @min(self.bottomRightRow(), other.bottomRightRow()),
            .col = @min(self.bottomRightCol(), other.bottomRightCol()),
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
    test "intersect with the same region" {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 10, .cols = 10 };
        // when:
        const actual = region.intersect(region);
        // then:
        try std.testing.expectEqualDeep(region, actual);
    }
};

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

        alloc: std.mem.Allocator,
        bitsets: []std.StaticBitSet(cols),

        pub fn initEmpty(alloc: std.mem.Allocator) !Self {
            var self: Self = .{ .alloc = alloc, .bitsets = try alloc.alloc(std.StaticBitSet(cols), rows) };
            self.clear();
            return self;
        }

        pub fn initFull(alloc: std.mem.Allocator) !Self {
            var self: Self = .{ .alloc = alloc, .bitsets = try alloc.alloc(std.StaticBitSet(cols), rows) };
            for (0..rows) |idx| {
                self.bitsets[idx] = std.StaticBitSet(cols).initFull();
            }
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.bitsets);
            self.bitsets = undefined;
        }

        pub fn clear(self: *Self) void {
            for (0..rows) |idx| {
                self.bitsets[idx] = std.StaticBitSet(cols).initEmpty();
            }
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
            return self.bitsets[row - 1].isSet(col - 1);
        }

        pub inline fn set(self: *Self, row: u8, col: u8) void {
            self.bitsets[row - 1].set(col - 1);
        }

        pub inline fn setAt(self: *Self, point: Point) void {
            self.set(point.row, point.col);
        }

        pub inline fn unset(self: *Self, row: u8, col: u8) void {
            self.bitsets[row - 1].unset(col - 1);
        }

        pub inline fn unsetAt(self: *Self, point: Point) void {
            self.unset(point.row, point.col);
        }

        pub inline fn setRowValue(
            self: *Self,
            row: u8,
            from_col: u8,
            count: u8,
            value: bool,
        ) void {
            self.bitsets[row - 1].setRangeValue(
                .{ .start = from_col - 1, .end = from_col + count - 1 },
                value,
            );
        }

        pub fn setRegionValue(self: *Self, region: Region, value: bool) void {
            if (region.top_left.row > rows) {
                return;
            }
            if (region.top_left.col > cols) {
                return;
            }
            const to_row = @min(rows, region.bottomRightRow()) + 1;
            const to_col = @min(cols, region.bottomRightCol());
            for (region.top_left.row..to_row) |r| {
                self.bitsets[r - 1].setRangeValue(
                    .{ .start = region.top_left.col - 1, .end = to_col },
                    value,
                );
            }
        }

        pub fn bilinearInterpolate(
            self: Self,
            alloc: std.mem.Allocator,
            comptime new_rows: u8,
            comptime new_cols: u8,
        ) !BitMap(new_rows, new_cols) {
            // https://meghal-darji.medium.com/implementing-bilinear-interpolation-for-image-resizing-357cbb2c2722
            var result: BitMap(new_rows, new_cols) = try BitMap(new_rows, new_cols).initEmpty(alloc);
            const v_scale: f16 = @as(f16, @floatFromInt(rows)) / new_rows;
            const h_scale: f16 = @as(f16, @floatFromInt(cols)) / new_cols;
            const k: f16 = 0.4;
            for (0..new_rows) |i| {
                for (0..new_cols) |j| {
                    const r: f16 = @as(f16, @floatFromInt(i)) * v_scale;
                    const c: f16 = @as(f16, @floatFromInt(j)) * h_scale;

                    const r_floor = @floor(r);
                    const r_ceil = @ceil(r);
                    const c_floor = @floor(c);
                    const c_ceil = @ceil(c);

                    if (r_floor == r_ceil and c_floor == c_ceil) {
                        result.bitsets[i].setValue(j, self.getf(r, c) > 0);
                        continue;
                    }

                    if (r_floor == r_ceil) {
                        const q1 = self.getf(r, c_floor);
                        const q2 = self.getf(r, c_ceil);
                        const q = q1 * (c_ceil - c) + q2 * (c - c_floor);
                        if (q > k) result.bitsets[i].set(j);
                        continue;
                    }

                    if (c_floor == c_ceil) {
                        const q1 = self.getf(r_floor, c);
                        const q2 = self.getf(r_ceil, c);
                        const q = q1 * (r_ceil - r) + q2 * (r - r_floor);
                        if (q > k) result.bitsets[i].set(j);
                        continue;
                    }

                    //      d1 d2
                    //  v1 ---c--- v2
                    //   |    |    | d3
                    //   r   r:c---|
                    //   |         | d4
                    //  v3-------v4
                    const v1: f16 = self.getf(r_floor, c_floor);
                    const v2: f16 = self.getf(r_floor, c_ceil);
                    const v3: f16 = self.getf(r_ceil, c_floor);
                    const v4: f16 = self.getf(r_ceil, r_ceil);

                    // Estimate the pixel value q using pixel values of neighbours
                    const d1 = c - c_floor;
                    const d2 = c_ceil - c;
                    const d3 = r - r_floor;
                    const d4 = r_ceil - r;
                    const q1 = v1 * d2 + v2 * d1;
                    const q2 = v3 * d2 + v4 * d1;
                    const q = q1 * d4 + q2 * d3;

                    if (q > k) result.bitsets[i].set(j);
                }
            }
            return result;
        }

        inline fn getf(self: Self, i: f16, j: f16) f16 {
            return if (self.bitsets[@intFromFloat(i)].isSet(@intFromFloat(j))) 1.0 else 0.0;
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
    defer bitmap.deinit();
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
    defer bitmap.deinit();
    const region = Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 5, .cols = 5 };

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
