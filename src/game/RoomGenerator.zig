/// The interface to generate dungeon inside a single region.
const std = @import("std");
const Dungeon = @import("Dungeon.zig");

const Self = @This();

ctx: *anyopaque,
generateFn: *const fn (ctx: *anyopaque, dungeon: *Dungeon, top_row: u8, left_col: u8, rows: u8, cols: u8) anyerror!void,

pub inline fn generateRoom(self: *Self, dungeon: *Dungeon, top_row: u8, left_col: u8, rows: u8, cols: u8) !void {
    try self.generateFn(self.ctx, dungeon, top_row, left_col, rows, cols);
}

pub fn simpleRooms() Self {
    return .{
        .ctx = undefined,
        .generateFn = SimpleRoomGenerator.generate,
    };
}

const SimpleRoomGenerator = struct {
    /// Create rectangle of walls inside the region.
    fn generate(_: *anyopaque, dungeon: *Dungeon, top_row: u8, left_col: u8, rows: u8, cols: u8) anyerror!void {
        const margin: u8 = 4;
        const r: u8 = top_row + margin;
        const c: u8 = left_col + margin;
        const rs: u8 = rows - margin;
        const cs: u8 = cols - margin;
        for (r..(r + rs)) |i| {
            const u: u8 = @intCast(i);
            if (u == r or u == (r + rs - 1)) {
                dungeon.setWalls(u, c, cs);
            } else {
                dungeon.setWall(u, c);
                dungeon.setWall(u, c + cs - 1);
            }
        }
    }
};
