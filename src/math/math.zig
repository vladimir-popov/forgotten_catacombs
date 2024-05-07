const std = @import("std");

pub const BinaryTree = @import("BinaryTree.zig");

test {
    std.testing.refAllDecls(@This());
}
