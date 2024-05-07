const std = @import("std");
const p = @import("primitives.zig");

const Rooms = @This();

pub const Room = struct {
    region: p.Region,
    createDoorFn: *const fn (room: Room, side: p.Side, rand: std.Random) p.Point,

    pub inline fn createDoor(self: Room, side: p.Side, rand: std.Random) p.Point {
        return self.createDoorFn(self, side, rand);
    }
};

kd_tree: std.ArrayList(std.DynamicBitSet),

pub fn init(alloc: std.mem.Allocator) !Rooms {
    _ = alloc;
    return undefined;
}

pub fn deinit(self: Rooms) void {
    _ = self;
}

pub fn add(self: *Rooms, room: Room) !void {
    _ = self;
    _ = room;
}

pub fn findInside(self: Rooms, region: p.Region) []*Room {
    _ = self;
    _ = region;
    return undefined;
}
