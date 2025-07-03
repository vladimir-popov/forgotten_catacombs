//! A set of entities ids. Used in the component-containers such as inventory or pile.
const std = @import("std");
const g = @import("../game_pkg.zig");

const Self = @This();

const UnderlyingMap = std.AutoHashMapUnmanaged(g.Entity, void);
pub const Iterator = UnderlyingMap.KeyIterator;

alloc: std.mem.Allocator,
underlying_map: UnderlyingMap = .empty,

pub fn empty(alloc: std.mem.Allocator) Self {
    return .{ .alloc = alloc, .underlying_map = .empty };
}

pub fn deinit(self: *Self) void {
    self.underlying_map.deinit(self.alloc);
}

pub fn clone(self: Self, alloc: std.mem.Allocator) !Self {
    return .{ .alloc = alloc, .underlying_map = try self.underlying_map.clone(alloc) };
}

pub fn size(self: Self) usize {
    return self.underlying_map.size;
}

pub fn iterator(self: Self) Iterator {
    return self.underlying_map.keyIterator();
}

pub fn add(self: *Self, item: g.Entity) !void {
    try self.underlying_map.put(self.alloc, item, {});
}

pub fn remove(self: *Self, item: g.Entity) bool {
    return self.underlying_map.remove(item);
}

pub fn jsonStringify(self: *const Self, jws: anytype) !void {
    try jws.beginArray();
    var itr = self.underlying_map.keyIterator();
    while (itr.next()) |entity| {
        try jws.write(entity.id);
    }
    try jws.endArray();
}

pub fn jsonParse(alloc: std.mem.Allocator, source: anytype, opts: std.json.ParseOptions) !Self {
    const value = try std.json.Value.jsonParse(alloc, source, opts);
    defer value.array.deinit();
    return try jsonParseFromValue(alloc, value, opts);
}

pub fn jsonParseFromValue(alloc: std.mem.Allocator, value: std.json.Value, _: std.json.ParseOptions) !Self {
    var result: Self = .{ .alloc = alloc, .underlying_map = .empty };
    for (value.array.items) |v| {
        try result.underlying_map.put(alloc, .{ .id = @intCast(v.integer) }, {});
    }
    return result;
}

pub fn eql(self: Self, other: Self) bool {
    if (self.underlying_map.size != other.underlying_map.size)
        return false;

    var self_itr = self.underlying_map.keyIterator();
    var other_itr = self.underlying_map.keyIterator();
    while (self_itr.next()) |s| {
        while (other_itr.next()) |o| {
            if (!std.meta.eql(s, o))
                return false;
        }
    }
    return true;
}
