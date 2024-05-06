const std = @import("std");
const p = @import("primitives.zig");

const Passages = @This();

const Passage = struct {
    corners: std.ArrayList(p.Point),

    pub fn create(alloc: std.mem.Allocator, from: p.Point, to: p.Point) !Passage {
        _ = alloc;
    }

    pub fn deinit(self: Passage) void {
        _ = self;
    }
};

pub fn init(alloc: std.mem.Allocator) Passages {
    _ = alloc;
}

pub fn deinit(self: Passages) void {
    _ = self;
}

pub fn findInside(self: Passages, region: p.Region) []const Passage {

}
