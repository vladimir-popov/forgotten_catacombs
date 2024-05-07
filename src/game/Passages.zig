const std = @import("std");
const p = @import("primitives.zig");

const Passages = @This();

pub const Passage = struct {
    corners: std.ArrayList(p.Point),

    pub fn create(alloc: std.mem.Allocator, from: p.Point, to: p.Point) !Passage {
        _ = from;
        _ = to;
        return .{ .corners = std.ArrayList(p.Point).init(alloc) };
    }

    pub fn deinit(self: Passage) void {
        _ = self;
    }

    pub fn createDoor(self: *Passage, rand: std.Random) !p.Point {
        _ = self;
        _ = rand;
        return undefined;
    }
};

pub fn init(alloc: std.mem.Allocator) !Passages {
    _ = alloc;
    return undefined;
}

pub fn deinit(self: Passages) void {
    _ = self;
}

pub fn add(self: *Passages, passage: Passage) !void {
    _ = self;
    _ = passage;
}

pub fn findInside(self: Passages, region: p.Region) []*Passage {
    _ = self;
    _ = region;
    return undefined;
}
