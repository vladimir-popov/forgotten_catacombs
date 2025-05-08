const std = @import("std");

/// The id of an entity.
id: u32,

// TODO benchmark
pub fn eql(self: @This(), other: anytype) bool {
    return switch (@typeInfo(@TypeOf(other))) {
        .optional => if (other == null) false else std.meta.eql(self, other.?),
        .@"struct" => std.meta.eql(self, other),
        else => false,
    };
}

pub fn parse(str: []const u8) ?@This() {
    return .{ .id = std.fmt.parseInt(u32, str, 10) catch return null };
}
