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
    /// Create rectangle of walls inside the region.
    fn generate(ptr: *anyopaque, walls: *Walls, region: p.Region) anyerror!Room {
        const self: *SimpleRoomGenerator = @ptrCast(@alignCast(ptr));
        const margin: u8 = self.rand.intRangeAtMost(u8, 1, 4);
        const r = region.top_left.row;
        const c = region.top_left.col;
        const rs: u8 = region.rows - margin;
        const cs: u8 = region.cols - margin;
        for (r..(r + rs)) |i| {
            const u: u8 = @intCast(i);
            if (u == r or u == (r + rs - 1)) {
                walls.setRowOfWalls(u, c, cs);
            } else {
                walls.setWall(u, c);
                walls.setWall(u, c + cs - 1);
            }
        }
        return .{
            .region = .{ .top_left = .{ .row = r, .col = c }, .rows = rs, .cols = cs },
            .createDoorFn = SimpleRoomGenerator.createDoor,
        };
    }

    fn createDoor(room: Room, side: p.Side, rand: std.Random) p.Point {
        return switch (side) {
            .top => .{
                .row = room.region.top_left.row,
                .col = rand.intRangeLessThan(u8, 0, room.region.cols) + room.region.top_left.col,
            },
            .bottom => .{
                .row = room.region.top_left.row + room.region.rows - 1,
                .col = rand.intRangeLessThan(u8, 0, room.region.cols) + room.region.top_left.col,
            },
            .left => .{
                .row = rand.intRangeLessThan(u8, 0, room.region.rows) + room.region.top_left.row,
                .col = room.region.top_left.col,
            },
            .right => .{
                .row = rand.intRangeLessThan(u8, 0, room.region.rows) + room.region.top_left.row,
                .col = room.region.top_left.col + room.region.cols - 1,
            },
        };

    }
};
