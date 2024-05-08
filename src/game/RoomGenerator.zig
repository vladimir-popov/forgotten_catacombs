const std = @import("std");
const p = @import("primitives.zig");
const Dungeon = @import("Dungeon.zig");
const Walls = Dungeon.Walls;
const Room = Dungeon.Room;

/// The interface of different algorithms to generate rooms with walls inside
/// the region.
const RoomGenerator = @This();

ctx: *anyopaque,
generateFn: *const fn (ctx: *anyopaque, walls: *Walls, region: p.Region) anyerror!Room,

/// Creates walls of the room inside the region.
/// Returns the actual region in which the room is inscribed in.
pub inline fn createRoom(self: RoomGenerator, walls: *Walls, region: p.Region) !Room {
    return try self.generateFn(self.ctx, walls, region);
}

/// The simplest rooms generator, which create rooms as walls inside the region.
pub const SimpleRoomGenerator = struct {
    rand: std.Random,

    pub fn generator(self: *SimpleRoomGenerator) RoomGenerator {
        return .{
            .ctx = self,
            .generateFn = SimpleRoomGenerator.generate,
        };
    }
    /// Creates walls inside the region with random padding in the range [0:2].
    /// Also, the count of rows and columns can be randomly reduced too in the same range.
    /// The minimal size of the region is 7x7.
    ///
    /// Example of the room inside the 7x7 region with padding 1
    /// (the room's region includes the '#' cells):
    ///
    ///  ________
    /// |       |
    /// |       |
    /// | ##### |
    /// | #   # |
    /// | ##### |
    /// |       |
    /// |       |
    /// ---------
    fn generate(ptr: *anyopaque, walls: *Walls, region: p.Region) anyerror!Room {
        std.debug.assert(region.rows > 6);
        std.debug.assert(region.cols > 6);

        const self: *SimpleRoomGenerator = @ptrCast(@alignCast(ptr));
        var room = region;
        const r_pad = self.rand.uintAtMost(u8, 2);
        const c_pad = self.rand.uintAtMost(u8, 2);
        room.top_left.row += r_pad;
        room.top_left.col += c_pad;
        room.rows -= (r_pad + self.rand.uintAtMost(u8, 2));
        room.cols -= (c_pad + self.rand.uintAtMost(u8, 2));

        for (room.top_left.row..(room.top_left.row + room.rows)) |r| {
            if (r == room.top_left.row or r == room.bottomRight().row) {
                walls.setRowOfWalls(@intCast(r), room.top_left.col, room.cols);
            } else {
                walls.setWall(@intCast(r), @intCast(room.top_left.col));
                walls.setWall(@intCast(r), @intCast(room.bottomRight().col));
            }
        }

        return room;
    }
};

test "generate a simple room" {
    // given:
    const rows = 12;
    const cols = 12;
    var walls = try Walls.initEmpty(std.testing.allocator, rows, cols);
    defer walls.deinit();
    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };

    var generator = SimpleRoomGenerator{ .rand = std.crypto.random };

    // when:
    const room = try generator.generator().createRoom(&walls, region);

    // then:
    try std.testing.expect(region.containsRegion(room));
    for (0..rows) |r_idx| {
        const r: u8 = @intCast(r_idx + 1);
        for (0..cols) |c_idx| {
            const c: u8 = @intCast(c_idx + 1);
            const cell = walls.isWall(r, c);
            const expect = room.containsPoint(r, c) and
                (r == room.top_left.row or r == room.bottomRight().row or
                c == room.top_left.col or c == room.bottomRight().col);
            try std.testing.expectEqual(expect, cell);
        }
    }
}
