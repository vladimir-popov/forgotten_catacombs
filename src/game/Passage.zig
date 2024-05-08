const std = @import("std");
const p = @import("primitives.zig");
const Walls = @import("Walls.zig");

const Self = @This();

corners: std.ArrayList(p.Point),

pub fn create(alloc: std.mem.Allocator, rand: std.Random, from: p.Point, to: p.Point, walls: *Walls) !Self {
    var corners = std.ArrayList(p.Point).init(alloc);
    try corners.append(from);
    try corners.append(to);
    _ = rand;
    _ = walls;
    return .{ .corners = corners };
}

pub fn deinit(self: Self) void {
    _ = self;
}
