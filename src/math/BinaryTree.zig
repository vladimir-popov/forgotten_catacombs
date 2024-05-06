const std = @import("std");

pub fn Node(comptime V: type) type {
    return struct {
        const NodeV = @This();

        parent: ?*NodeV = null,
        left: ?*NodeV = null,
        right: ?*NodeV = null,
        value: V,

        pub inline fn leftValue(self: NodeV) ?V {
            if (self.left) |first| {
                return first.value;
            } else {
                return null;
            }
        }

        pub inline fn rightValue(self: NodeV) ?V {
            if (self.right) |second| {
                return second.value;
            } else {
                return null;
            }
        }

        pub inline fn isLeaf(self: *const NodeV) bool {
            return self.left == null and self.right == null;
        }

        /// Splits the node until the handler returns value.
        pub fn split(
            self: *NodeV,
            alloc: std.mem.Allocator,
            init_depth: u8,
            handler: SplitHandler,
        ) !void {
            std.debug.assert(self.left == null);
            std.debug.assert(self.right == null);

            const maybe_values = try handler.split(handler.ptr, self, init_depth);
            if (maybe_values) |values| {
                self.left = try alloc.create(NodeV);
                self.left.?.* = NodeV{
                    .parent = self,
                    .value = values[0],
                };
                try self.left.?.split(alloc, init_depth + 1, handler);

                self.right = try alloc.create(NodeV);
                self.right.?.* = NodeV{
                    .parent = self,
                    .value = values[1],
                };
                try self.right.?.split(alloc, init_depth + 1, handler);
            }
        }

        /// Traverse all nodes of this tree in depth, and pass them to the callback.
        pub fn traverse(self: *NodeV, init_depth: u8, handler: TraverseHandler) !void {
            try handler.handle(handler.ptr, self, init_depth);
            if (self.left) |first| {
                try traverse(first, init_depth + 1, handler);
            }
            if (self.right) |second| {
                try traverse(second, init_depth + 1, handler);
            }
        }

        pub fn fold(self: NodeV, depth: u8, handler: FoldHandler) !V {
            if (self.isLeaf()) return self.value;

            if (self.left) |left| {
                if (self.right) |right| {
                    return try handler.combine(
                        handler.ptr,
                        try left.fold(depth + 1, handler),
                        try right.fold(depth + 1, handler),
                        depth,
                    );
                } else {
                    return try left.fold(depth + 1, handler);
                }
            } else {
                @panic("The tree is not balanced");
            }
        }

        pub const SplitHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// node - the current node of the tree, which should be split
            /// depth - the current depth
            split: *const fn (ptr: *anyopaque, node: *NodeV, depth: u8) anyerror!?struct { V, V },
        };

        pub const TraverseHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// node - the current node of the tree
            /// depth - the current depth
            handle: *const fn (ptr: *anyopaque, node: *NodeV, depth: u8) anyerror!void,
        };

        pub const FoldHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// left_value - the value of the left node
            /// right_value - the value of the right node
            /// depth - the current depth of the tree
            combine: *const fn (ptr: *anyopaque, left_value: V, right_value: ?V, depth: u8) anyerror!V,
        };
    };
}

test "split/fold" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    const divider = Node(u8).SplitHandler{ .ptr = undefined, .split = divide };
    const summator = Node(u8).FoldHandler{ .ptr = undefined, .combine = sum };
    var tree = Node(u8){ .value = 8 };

    // when:
    try tree.split(arena.allocator(), 0, divider);
    const result = try tree.fold(0, summator);

    // then:
    try std.testing.expectEqual(8, result);
}

// Test utils //

fn divide(_: *anyopaque, node: *Node(u8), _: u8) anyerror!?struct { u8, u8 } {
    const half: u8 = node.value / 2;
    return if (half > 0) .{ half, half } else null;
}

fn sum(_: *anyopaque, x: u8, y: ?u8, _: u8) anyerror!u8 {
    return x + y.?;
}
