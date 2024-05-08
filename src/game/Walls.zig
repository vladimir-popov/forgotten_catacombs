const std = @import("std");
const p = @import("primitives.zig");

const Walls = @This();

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

pub fn isWall(self: Walls, row: u8, col: u8) bool {
    if (row < 1 or row > self.bitsets.items.len)
        std.debug.panic("The row {d} is out of bound. Total rows count is {d}", .{ row, self.rowsCount() });
    const walls_row = self.bitsets.items[row - 1];
    if (col < 1 or col > walls_row.capacity())
        std.debug.panic("The column {d} is out of bound. Total columns count is {d}", .{ col, self.colsCount() });
    return walls_row.isSet(col - 1);
}

pub fn setWall(self: *Walls, row: u8, col: u8) void {
    self.bitsets.items[row - 1].set(col - 1);
}

pub fn setRowOfWalls(self: *Walls, row: u8, from_col: u8, count: u8) void {
    self.bitsets.items[row - 1].setRangeValue(.{ .start = from_col - 1, .end = from_col + count - 1 }, true);
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
            const expect = !region.containsPoint(@intCast(r), @intCast(c_idx + 1));
            try std.testing.expectEqual(expect, cell);
        }
    }
}
