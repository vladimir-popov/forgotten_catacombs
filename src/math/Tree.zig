const std = @import("std");

pub fn Node(comptime V: type) type {
    return struct {
        const NodeV = @This();

        parent: ?*NodeV = null,
        first: ?*NodeV = null,
        second: ?*NodeV = null,
        value: V,

        pub inline fn firstValue(self: NodeV) ?V {
            if (self.first) |first| {
                return first.value;
            } else {
                return null;
            }
        }

        pub inline fn secondValue(self: NodeV) ?V {
            if (self.second) |second| {
                return second.value;
            } else {
                return null;
            }
        }

        pub inline fn isLeaf(self: *const NodeV) bool {
            return self.first == null and self.second == null;
        }

        /// Splits the node until the handler returns value.
        pub fn split(
            self: *NodeV,
            alloc: std.mem.Allocator,
            init_depth: u8,
            handler: SplitHandler,
        ) !void {
            std.debug.assert(self.first == null);
            std.debug.assert(self.second == null);

            const maybe_values = try handler.split(handler.ptr, self, init_depth);
            if (maybe_values) |values| {
                self.first = try alloc.create(NodeV);
                self.first.?.* = NodeV{
                    .parent = self,
                    .value = values[0],
                };
                try self.first.?.split(alloc, init_depth + 1, handler);

                self.second = try alloc.create(NodeV);
                self.second.?.* = NodeV{
                    .parent = self,
                    .value = values[1],
                };
                try self.second.?.split(alloc, init_depth + 1, handler);
            }
        }

        /// Traverse all nodes of this tree in depth, and pass them to the callback.
        pub fn traverse(self: *NodeV, init_depth: u8, handler: TraverseHandler) !void {
            try handler.handle(handler.ptr, self, init_depth);
            if (self.first) |first| {
                try traverse(first, init_depth + 1, handler);
            }
            if (self.second) |second| {
                try traverse(second, init_depth + 1, handler);
            }
        }

        pub fn fold(self: NodeV, handler: FoldHandler) !V {
            if (self.isLeaf()) return self.value;

            if (self.first) |first| {
                if (self.second) |second| {
                    return try handler.combine(handler.ptr, try first.fold(handler), try second.fold(handler));
                } else {
                    return try first.fold(handler);
                }
            } else {
                @panic("The tree is not balanced");
            }
        }

        pub const SplitHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// node - the current node of the treem which should be split
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
            /// node - the current node of the tree, which is the parent of leafs.
            combine: *const fn (ptr: *anyopaque, first_value: V, second_value: ?V) anyerror!V,
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
    const result = try tree.fold(summator);

    // then:
    try std.testing.expectEqual(8, result);
}

// Test utils //

fn divide(_: *anyopaque, node: *Node(u8), _: u8) anyerror!?struct { u8, u8 } {
    const half: u8 = node.value / 2;
    return if (half > 0) .{ half, half } else null;
}

fn sum(_: *anyopaque, x: u8, y: ?u8) anyerror!u8 {
    return x + y.?;
}
