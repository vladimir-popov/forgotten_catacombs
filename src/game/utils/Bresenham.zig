//! This is an iterator of points on a line from the `start` point
//! to the `end` point (both exclusive).
//! Iteration uses the [Bresenham's line algorithm](https://en.wikipedia.org/wiki/Bresenham%27s_line_algorithm):
//! ```
//! plotLine(x0, y0, x1, y1)
//!    dx = abs(x1 - x0)
//!    sx = x0 < x1 ? 1 : -1
//!    dy = -abs(y1 - y0)
//!    sy = y0 < y1 ? 1 : -1
//!    error = dx + dy
//!
//!    while true
//!        plot(x0, y0)
//!        e2 = 2 * error
//!        if e2 >= dy
//!            if x0 == x1 break
//!            error = error + dy
//!            x0 = x0 + sx
//!        end if
//!        if e2 <= dx
//!            if y0 == y1 break
//!            error = error + dx
//!            y0 = y0 + sy
//!        end if
//!    end while
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const Point = g.primitives.Point;

const Self = @This();

x0: i32,
y0: i32,
x1: i32,
y1: i32,
dx: i32,
sx: i32,
dy: i32,
sy: i32,
err: i32,

pub fn init(start: Point, end: Point) Self {
    var self: Self = undefined;
    self.x0 = @intCast(start.col);
    self.y0 = @intCast(start.row);
    self.x1 = @intCast(end.col);
    self.y1 = @intCast(end.row);
    self.dx = abs(self.x1 - self.x0);
    self.dy = -abs(self.y1 - self.y0);
    self.sx = if (self.x0 < self.x1) 1 else -1;
    self.sy = if (self.y0 < self.y1) 1 else -1;
    self.err = self.dx + self.dy;
    return self;
}

inline fn abs(x: i32) i32 {
    return @intCast(@abs(x));
}

pub fn next(self: *Self) ?Point {
    const e2 = 2 * self.err;
    if (e2 >= self.dy) {
        if (self.x0 == self.x1) return null;
        self.err += self.dy;
        self.x0 += self.sx;
    }
    if (e2 <= self.dx) {
        if (self.y0 == self.y1) return null;
        self.err += self.dx;
        self.y0 += self.sy;
    }
    // exclude the end
    if (self.x0 == self.x1 and self.y0 == self.y1) return null;
    return Point.init(@intCast(self.y0), @intCast(self.x0));
}

test "test case 1" {
    const start = Point.init(0, 0);
    const end = Point.init(4, 4);
    const expected = [_]Point{ .init(1, 1), .init(2, 2), .init(3, 3) };
    var actual: [expected.len]Point = undefined;

    var i: usize = 0;
    var itr = Self.init(start, end);
    while (itr.next()) |point| {
        actual[i] = point;
        i += 1;
    }

    try std.testing.expectEqual(expected, actual);
}

test "test case 2" {
    const start = Point.init(0, 0);
    const end = Point.init(2, 4);
    const expected = [_]Point{ .init(1, 1), .init(1, 2), .init(2, 3) };
    var actual: [expected.len]Point = undefined;

    var i: usize = 0;
    var itr = Self.init(start, end);
    while (itr.next()) |point| {
        actual[i] = point;
        i += 1;
    }

    try std.testing.expectEqual(expected, actual);
}

test "test case 3" {
    const start = Point.init(0, 5);
    const end = Point.init(2, 0);
    const expected = [_]Point{ .init(0, 4), .init(1, 3), .init(1, 2), .init(2, 1) };
    var actual: [expected.len]Point = undefined;

    var i: usize = 0;
    var itr = Self.init(start, end);
    while (itr.next()) |point| {
        actual[i] = point;
        i += 1;
    }

    try std.testing.expectEqual(expected, actual);
}
