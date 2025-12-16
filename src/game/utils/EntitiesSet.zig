//! A set of entities ids. Used in the component-containers such as inventory or pile.
//! Has special methods for saving/loading all contained entities.
const std = @import("std");
const g = @import("../game_pkg.zig");

const Self = @This();

const UnderlyingMap = std.AutoHashMapUnmanaged(g.Entity, void);
pub const Iterator = UnderlyingMap.KeyIterator;

alloc: std.mem.Allocator,
underlying_map: *UnderlyingMap,

pub fn init(alloc: std.mem.Allocator) !Self {
    const self: Self = .{ .alloc = alloc, .underlying_map = try alloc.create(UnderlyingMap) };
    self.underlying_map.* = .empty;
    return self;
}

pub fn deinit(self: *Self) void {
    self.underlying_map.deinit(self.alloc);
    self.alloc.destroy(self.underlying_map);
}

pub fn clone(self: Self, alloc: std.mem.Allocator) !Self {
    return .{ .alloc = alloc, .underlying_map = try self.underlying_map.clone(alloc) };
}

pub fn contains(self: Self, item: g.Entity) bool {
    return self.underlying_map.contains(item);
}

/// - `writer` - as example: `*persistance.Writer(Runtime.FileWriter.Writer)`
pub fn save(self: Self, writer: anytype) !void {
    try writer.beginCollection();
    var itr = self.iterator();
    while (itr.next()) |entity| {
        try writer.writeEntity(entity.*);
    }
    try writer.endCollection();
}

/// - `reader` - as example: `*persistance.Reader(Runtime.FileReader.Reader)`
pub fn load(reader: anytype) !Self {
    const set = try init(reader.registry.allocator());
    try reader.beginCollection();
    while (!try reader.isCollectionEnd()) {
        try set.add(try reader.readEntity());
    }
    try reader.endCollection();
    return set;
}

pub fn size(self: Self) usize {
    return self.underlying_map.size;
}

pub fn iterator(self: Self) Iterator {
    return self.underlying_map.keyIterator();
}

pub fn add(self: Self, item: g.Entity) !void {
    try self.underlying_map.put(self.alloc, item, {});
}

pub fn remove(self: Self, item: g.Entity) bool {
    return self.underlying_map.remove(item);
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

pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
    _ = try writer.write("[ ");
    var itr = self.underlying_map.keyIterator();
    while (itr.next()) |entity| {
        try writer.print("{d}", .{entity.id});
        if (itr.len > 1)
            _ = try writer.write(", ");
    }
    _ = try writer.write(" ]");
}
