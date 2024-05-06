const std = @import("std");

pub const Tree = @import("Tree.zig");

test {
    std.testing.refAllDecls(@This());
}
