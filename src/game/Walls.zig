const std = @import("std");

const Walls = @This();

bitsets: std.ArrayList(std.DynamicBitSet),

pub fn initEmpty(alloc: std.mem.Allocator, rows: u8, cols: u8) !Walls {
    var bitsets = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
    for (0..rows) |_| {
        const row = bitsets.addOneAssumeCapacity();
        row.* = try std.DynamicBitSet.initEmpty(alloc, cols);
    }
    return bitsets;
}

pub fn deinit(self: Walls) void {
    for (self.bitsets.items) |*row| {
        row.deinit();
    }
    self.bitsets.deinit();
}

pub fn isWall(self: Walls, row: u8, col: u8) bool {
    if (row < 1 or row >= self.walls.items.len)
        return true;
    const walls_row = self.bitsets.items[row - 1];
    if (col < 1 or col >= walls_row.capacity())
        return true;
    return walls_row.isSet(col - 1);
}

pub fn setWall(self: *Walls, row: u8, col: u8) void {
    self.bitsets.items[row - 1].set(col - 1);
}

pub fn setRowOfWalls(self: *Walls, row: u8, from_col: u8, count: u8) void {
    self.bitsets.items[row - 1].setRangeValue(.{ .start = from_col - 1, .end = from_col + count - 1 }, true);
}
