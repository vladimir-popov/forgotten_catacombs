//! Numeric identifier of an entity wrapped to a structure for type safety.
const std = @import("std");

pub const IdType = u32;

/// The id of an entity.
id: IdType,

pub inline fn eql(self: @This(), other: anytype) bool {
    return switch (@typeInfo(@TypeOf(other))) {
        .optional => if (other == null) false else std.meta.eql(self, other.?),
        .@"struct" => std.meta.eql(self, other),
        else => false,
    };
}

pub fn parse(str: []const u8) ?@This() {
    return .{ .id = std.fmt.parseInt(IdType, str, 10) catch return null };
}
