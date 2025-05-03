//! This module contains algorithms, data structures, and primitive types,
//! such as geometry primitives, which are not game domain objects.
const std = @import("std");

const log = std.log.scoped(.primitives);

/// The absolute difference between two numbers
pub inline fn diff(comptime T: type, a: T, b: T) T {
    return @max(a, b) - @min(a, b);
}

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

/// The coordinates of a point.
pub const Point = struct {
    row: u8 = 0,
    col: u8 = 0,

    pub fn init(r: u8, c: u8) Point {
        return .{ .row = r, .col = c };
    }

    pub fn format(
        self: Point,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
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

    pub inline fn eql(self: Point, other: Point) bool {
        return self.row == other.row and self.col == other.col;
    }

    pub inline fn near(self: Point, other: Point) bool {
        return @max(self.row, other.row) - @min(self.row, other.row) < 2 and
            @max(self.col, other.col) - @min(self.col, other.col) < 2;
    }

    pub fn distanceTo(self: Point, other: Point) f16 {
        const a: f16 = @floatFromInt(diff(u8, self.row, other.row));
        const b: f16 = @floatFromInt(diff(u8, self.col, other.col));
        return @sqrt(a * a + b * b);
    }

    /// Two points on the same side of the line should have similar sign.
    /// Result == 0 means that point is on the line.
    pub fn sideOfLine(self: Point, line_start: Point, line_end: Point) i16 {
        // A=(x1,y1) to B=(x2,y2) a point P=(x,y)
        const x: i16 = @intCast(self.col);
        const y: i16 = @intCast(self.row);
        const x1: i16 = @intCast(line_start.col);
        const y1: i16 = @intCast(line_start.row);
        const x2: i16 = @intCast(line_end.col);
        const y2: i16 = @intCast(line_end.row);
        return (x - x1) * (y2 - y1) - (y - y1) * (x2 - x1);
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

    pub fn init(rows: u8, cols: u8) Region {
        return .{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols };
    }

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

    pub inline fn bottomRight(self: Region) Point {
        return .{ .row = self.bottomRightRow(), .col = self.bottomRightCol() };
    }

    pub inline fn topRight(self: Region) Point {
        return .{ .row = self.top_left.row, .col = self.bottomRightCol() };
    }

    pub inline fn bottomLeft(self: Region) Point {
        return .{ .row = self.bottomRightRow(), .col = self.top_left.col };
    }

    pub inline fn center(self: Region) Point {
        return .{ .row = self.top_left.row + self.rows / 2, .col = self.top_left.col + self.cols / 2 };
    }

    /// Returns the area of this region.
    pub inline fn area(self: Region) u16 {
        return std.math.mulWide(u8, self.rows, self.cols);
    }

    /// Multiplies rows by `v_scale` and columns by `h_scale`
    pub fn scale(self: *Region, v_scale: f16, h_scale: f16) void {
        const rows: f16 = @floatFromInt(self.rows);
        const cols: f16 = @floatFromInt(self.cols);
        self.rows = @intFromFloat(@round(rows * v_scale));
        self.cols = @intFromFloat(@round(cols * h_scale));
        std.debug.assert(self.rows > 0);
        std.debug.assert(self.cols > 0);
    }

    pub fn scaled(self: Region, v_scale: f16, h_scale: f16) Region {
        var reg = self;
        reg.scale(v_scale, h_scale);
        return reg;
    }

    /// Returns true if the point is inside the region including the borders.
    pub inline fn containsPoint(self: Region, point: Point) bool {
        return self.top_left.row <= point.row and point.row <= self.bottomRightRow() and
            self.top_left.col <= point.col and point.col <= self.bottomRightCol();
    }

    /// Returns true if the point is inside the region excluding the borders.
    pub inline fn containsPointInside(self: Region, point: Point) bool {
        return self.top_left.row < point.row and point.row < self.bottomRightRow() and
            self.top_left.col < point.col and point.col < self.bottomRightCol();
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

    pub fn centralizeAround(self: *Region, target_center: Point) void {
        self.top_left.row = if (target_center.row > (self.rows / 2)) target_center.row - (self.rows / 2) else 1;
        self.top_left.col = if (target_center.col > (self.cols / 2)) target_center.col - (self.cols / 2) else 1;
    }

    /// Splits vertically the region in two if it possible. The first one contains the top
    /// left corner and `cols` columns. The second has the other part.
    /// If splitting is impossible, returns null.
    /// ┌───┬───┐
    /// │ 0 │ 1 │
    /// └───┴───┘
    pub fn splitVertically(self: Region, cols: u8) struct { Region, Region } {
        std.debug.assert(0 < cols);
        std.debug.assert(cols < self.cols);
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
    }

    /// Splits horizontally the region in two if it possible. The first one contains the top
    /// left corner and `rows` rows. The second has the other part.
    /// If splitting is impossible, returns null.
    /// ┌───┐
    /// │ 0 │
    /// ├───┤
    /// │ 1 │
    /// └───┘
    pub fn splitHorizontally(self: Region, rows: u8) struct { Region, Region } {
        std.debug.assert(0 < rows);
        std.debug.assert(rows < self.rows);
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
    }

    /// Makes copy of this region, and crops all rows before the `row` if it possible,
    /// or returns the copy without changes.
    ///
    /// ┌---┐
    /// ¦   ¦
    /// ├───┤ < row (exclusive)
    /// │ r │
    /// └───┘
    pub fn croppedHorizontallyAfter(self: Region, row: u8) ?Region {
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

    test croppedHorizontallyAfter {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 3 };
        // when:
        const result = region.croppedHorizontallyAfter(2);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 3, .col = 1 }, .rows = 3, .cols = 3 },
            result,
        );
    }

    /// Makes copy of this region, and crops all cols before the `col` if it possible,
    /// or returns the copy without changes.
    ///
    /// ┌---┬───┐
    /// ¦   │ r │
    /// └---┴───┘
    ///     ^
    ///     col (exclusive)
    pub fn croppedVerticallyAfter(self: Region, col: u8) ?Region {
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

    test croppedVerticallyAfter {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 };
        // when:
        const result = region.croppedVerticallyAfter(2);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 1, .col = 3 }, .rows = 3, .cols = 3 },
            result,
        );
    }

    /// Makes copy of this region, and crops all rows after the `row` (exclusive) if it possible,
    /// or returns the copy without changes.
    ///
    /// ┌───┐
    /// │ r │
    /// ├───┤ < row (exclusive)
    /// ¦   ¦
    /// └---┘
    pub fn croppedHorizontallyTo(self: Region, row: u8) ?Region {
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

    test croppedHorizontallyTo {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 5, .cols = 3 };
        // when:
        const result = region.croppedHorizontallyTo(3);
        // then:
        try std.testing.expectEqualDeep(
            Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 2, .cols = 3 },
            result,
        );
    }

    /// Makes copy of this region, and crops all cols after the `col` (exclusive) if it possible,
    /// or returns the copy without changes.
    ///
    /// ┌───┬---┐
    /// │ r │   ¦
    /// └───┴---┘
    ///     ^
    ///     col (exclusive)
    pub fn croppedVerticallyTo(self: Region, col: u8) ?Region {
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

    test croppedVerticallyTo {
        // given:
        const region = Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 };
        // when:
        const result = region.croppedVerticallyTo(3);
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
        const top_left = Point{
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

        pub inline fn setAt(self: *Self, point: Point) void {
            self.set(point.row, point.col);
        }

        pub inline fn unset(self: *Self, row: u8, col: u8) void {
            if (isOutside(row, col)) return;
            self.bitsets[row - 1].unset(col - 1);
        }

        pub inline fn unset0(self: *Self, row_idx: usize, col_idx: usize) void {
            self.bitsets[row_idx].unset(col_idx);
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
            if (row == 0 or row >= rows) return;
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
