const std = @import("std");

pub const BitMap = @import("BitMap.zig").BitMap;
pub const Bresenham = @import("Bresenham.zig");
pub const DijkstraMap = @import("DijkstraMap.zig");
pub const EntitiesSet = @import("EntitiesSet.zig");
pub const Preset = @import("Preset.zig").Preset;
pub const Set = @import("Set.zig").Set;
pub const SegmentedList = @import("segmented_list.zig").SegmentedList;

pub inline fn isDebug() bool {
    return switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => true,
        else => false,
    };
}

pub fn assert(p: bool, comptime fmt: []const u8, args: anytype) void {
    if (isDebug()) {
        if (!p) std.debug.panic(fmt, args);
    }
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

test {
    std.testing.refAllDecls(@This());
}
