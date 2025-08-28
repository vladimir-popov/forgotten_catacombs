const std = @import("std");

pub const BitMap = @import("BitMap.zig").BitMap;
pub const DijkstraMap = @import("DijkstraMap.zig");
pub const EntitiesSet = @import("EntitiesSet.zig");
pub const Preset = @import("Preset.zig").Preset;
pub const Set = @import("Set.zig").Set;

pub inline fn isDebug() bool {
    return switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => true,
        else => false,
    };
}

pub fn toStringWithListOf(tagged_unions: anytype) ToString.List(@typeInfo(@TypeOf(tagged_unions)).pointer.child) {
    return ToString.List(@typeInfo(@TypeOf(tagged_unions)).pointer.child){ .values = tagged_unions };
}

const ToString = struct {
    fn List(comptime T: type) type {
        return struct {
            const Self = @This();

            values: []const T,

            pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
                for (self.values) |value| {
                    try writer.print("\t{any}\n", .{value});
                }
            }
        };
    }
};
