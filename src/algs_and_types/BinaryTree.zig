const std = @import("std");

/// The Node of the BinaryTree.
pub fn Node(comptime V: type) type {
    return struct {
        const NodeV = @This();

        parent: ?*NodeV = null,
        left: ?*NodeV = null,
        right: ?*NodeV = null,
        depth: u8 = 0,
        value: V,
        lessThan: *const fn (x: V, y: V) bool,

        /// Creates a single root node of the binary tree.
        pub fn root(
            alloc: std.mem.Allocator,
            value: V,
            lessThan: *const fn (x: V, y: V) bool,
        ) !*Node(V) {
            const node = try alloc.create(NodeV);
            node.* = .{ .value = value, .lessThan = lessThan };
            return node;
        }

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
            splitter: SplitHandler,
        ) !void {
            std.debug.assert(self.left == null);
            std.debug.assert(self.right == null);
            var node: *NodeV = self;
            var another: ?*NodeV = null;
            while (true) {
                const maybe_values = try splitter.split(splitter.ptr, node);
                if (maybe_values) |values| {
                    node.left = try alloc.create(NodeV);
                    node.left.?.* = NodeV{
                        .parent = node,
                        .lessThan = node.lessThan,
                        .depth = node.depth + 1,
                        .value = values[0],
                    };
                    node.right = try alloc.create(NodeV);
                    node.right.?.* = NodeV{
                        .parent = node,
                        .lessThan = node.lessThan,
                        .depth = node.depth + 1,
                        .value = values[1],
                    };

                    if (another == null)
                        another = node.right;

                    node = node.left.?;
                } else if (another) |right| {
                    node = right;
                    another = null;
                } else {
                    break;
                }
            }
        }

        pub fn add(self: *NodeV, alloc: std.mem.Allocator, value: V) !void {
            if (self.lessThan(self.value, value)) {
                if (self.right) |right| {
                    try right.add(alloc, value);
                } else {
                    self.right = try alloc.create(NodeV);
                    self.right.?.* = NodeV{
                        .parent = self,
                        .lessThan = self.lessThan,
                        .depth = self.depth + 1,
                        .value = value,
                    };
                }
            } else {
                if (self.left) |left| {
                    try left.add(alloc, value);
                } else {
                    self.left = try alloc.create(NodeV);
                    self.left.?.* = NodeV{
                        .parent = self,
                        .lessThan = self.lessThan,
                        .depth = self.depth + 1,
                        .value = value,
                    };
                }
            }
        }

        /// Traverse all nodes of this tree in depth, and pass them to the callback.
        pub fn traverse(self: *NodeV, alloc: std.mem.Allocator, handler: TraverseHandler) !void {
            var stack = std.ArrayList(*NodeV).init(alloc);
            defer stack.deinit();
            try stack.append(self);
            while (stack.popOrNull()) |node| {
                try handler.handle(handler.ptr, node);
                if (node.right) |right| {
                    try stack.append(right);
                }
                if (node.left) |left| {
                    try stack.append(left);
                }
            }
        }

        pub fn fold(self: NodeV, handler: FoldHandler) !V {
            if (self.left) |left| {
                if (self.right) |right| {
                    return try handler.combine(
                        handler.ptr,
                        try left.fold(handler),
                        try right.fold(handler),
                        self.depth + 1,
                    );
                } else {
                    return try left.fold(handler);
                }
            } else if (self.right) |right| {
                return try right.fold(handler);
            } else {
                return self.value;
            }
        }

        pub const SplitHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// node - the current node of the tree, which should be split
            split: *const fn (ptr: *anyopaque, node: *NodeV) anyerror!?struct { V, V },
        };

        pub const TraverseHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// node - the current node of the tree
            handle: *const fn (ptr: *anyopaque, node: *NodeV) anyerror!void,
        };

        pub const FoldHandler = struct {
            ptr: *anyopaque,
            /// ptr - pointer to the context of the handler
            /// left_value - the value of the left node
            /// right_value - the value of the right node
            /// depth - the current depth of the tree
            combine: *const fn (ptr: *anyopaque, left_value: V, right_value: V, depth: u8) anyerror!V,
        };
    };
}

test "split/fold" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    const alloc = arena.allocator();

    const divider = Node(u8).SplitHandler{ .ptr = undefined, .split = divide };
    const summator = Node(u8).FoldHandler{ .ptr = undefined, .combine = sum };
    var tree = try Node(u8).root(alloc, 8, compareU8);

    // when:
    try tree.split(alloc, divider);
    const result = try tree.fold(summator);

    // then:
    try std.testing.expectEqual(8, result);
}

test "add/traverse" {
    // given:
    const TraverseValidate = struct {
        const Self = @This();

        actual_values: []u8,
        actual_depths: []u8,
        idx: u8,

        fn handler(self: *Self) Node(u8).TraverseHandler {
            return .{ .ptr = self, .handle = accumulate_actual };
        }

        fn accumulate_actual(ptr: *anyopaque, node: *Node(u8)) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            std.debug.print("{d}\n", .{node.value});
            // then:
            self.actual_values[self.idx] = node.value;
            self.actual_depths[self.idx] = node.depth;
            self.idx += 1;
        }
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    const alloc = arena.allocator();
    //          3
    //      1       5
    //        2   4   6
    var tree = try Node(u8).root(alloc, 3, compareU8);
    try tree.add(alloc, 1);
    try tree.add(alloc, 2);
    try tree.add(alloc, 5);
    try tree.add(alloc, 4);
    try tree.add(alloc, 6);

    const expected_values = [_]u8{ 1, 2, 3, 4, 5, 6 };
    const epxected_depths = [_]u8{ 0, 1, 1, 2, 2, 2 };

    var actual_values = [_]u8{ 0, 0, 0, 0, 0, 0 };
    var actual_depths = [_]u8{ 0, 0, 0, 0, 0, 0 };

    var validation = TraverseValidate{
        .actual_values = &actual_values,
        .actual_depths = &actual_depths,
        .idx = 0,
    };

    // when:
    try tree.traverse(alloc, validation.handler());

    // then:
    std.mem.sort(u8, &actual_values, {}, lessThanU8);
    try std.testing.expectEqualSlices(u8, &expected_values, &actual_values);
    std.mem.sort(u8, &actual_depths, {}, lessThanU8);
    try std.testing.expectEqualSlices(u8, &epxected_depths, &actual_depths);
}

// Test utils //

fn lessThanU8(_: void, x: u8, y: u8) bool {
    return compareU8(x, y);
}

fn compareU8(x: u8, y: u8) bool {
    return x < y;
}

fn divide(_: *anyopaque, node: *Node(u8)) anyerror!?struct { u8, u8 } {
    const half: u8 = node.value / 2;
    return if (half > 0) .{ half, half } else null;
}

fn sum(_: *anyopaque, x: u8, y: u8, _: u8) anyerror!u8 {
    return x + y;
}
