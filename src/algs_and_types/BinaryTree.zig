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
        compare: *const fn (depth: u8, x: V, y: V) i8,

        /// Creates a single root node of the binary tree.
        ///
        /// compare - the function to compare values. It should return -1 if x < y, 1 if x > y, and 0
        /// otherwise. Additionally, this function receive the current depth of the tree. It makes possible
        /// to use this tree as KdTree.
        pub fn root(
            alloc: std.mem.Allocator,
            value: V,
            compare: *const fn (depth: u8, x: V, y: V) i8,
        ) !*Node(V) {
            const node = try alloc.create(NodeV);
            node.* = .{ .value = value, .compare = compare };
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
                    std.debug.assert(node.compare(node.depth, values[0], values[1]) < 1);

                    node.left = try alloc.create(NodeV);
                    node.left.?.* = NodeV{
                        .parent = node,
                        .compare = node.compare,
                        .depth = node.depth + 1,
                        .value = values[0],
                    };
                    node.right = try alloc.create(NodeV);
                    node.right.?.* = NodeV{
                        .parent = node,
                        .compare = node.compare,
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
            if (self.compare(self.depth, value, self.value) == 1) {
                if (self.right) |right| {
                    try right.add(alloc, value);
                } else {
                    self.right = try alloc.create(NodeV);
                    self.right.?.* = NodeV{
                        .parent = self,
                        .compare = self.compare,
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
                        .compare = self.compare,
                        .depth = self.depth + 1,
                        .value = value,
                    };
                }
            }
        }

        /// Traverse all nodes of this tree in depth, and pass them to the callback.
        pub fn traverse(self: *NodeV, handler: TraverseHandler) !void {
            try handler.handle(handler.ptr, self);
            if (self.left) |first| {
                try traverse(first, handler);
            }
            if (self.right) |second| {
                try traverse(second, handler);
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

        expected_values: []const u8,
        epxected_depths: []const u8,
        idx: u8,

        fn handler(self: *Self) Node(u8).TraverseHandler {
            return .{ .ptr = self, .handle = check };
        }

        fn check(ptr: *anyopaque, node: *Node(u8)) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            try std.testing.expectEqual(self.expected_values[self.idx], node.value);
            try std.testing.expectEqual(self.epxected_depths[self.idx], node.depth);
            self.idx += 1;
        }
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    const alloc = arena.allocator();

    var tree = try Node(u8).root(alloc, 3, compareU8);
    const expected_values = [_]u8{ 3, 1, 2, 5, 4, 6 };
    const epxected_depths = [_]u8{ 0, 1, 2, 1, 2, 2 };
    var validation = TraverseValidate{
        .expected_values = &expected_values,
        .epxected_depths = &epxected_depths,
        .idx = 0,
    };

    // when:
    try tree.add(alloc, 1);
    try tree.add(alloc, 2);
    try tree.add(alloc, 5);
    try tree.add(alloc, 4);
    try tree.add(alloc, 6);

    // then:
    try tree.traverse(validation.handler());
}

// Test utils //

fn compareU8(_: u8, x: u8, y: u8) i8 {
    return if (x > y)
        1
    else if (x < y)
        -1
    else
        0;
}

fn divide(_: *anyopaque, node: *Node(u8)) anyerror!?struct { u8, u8 } {
    const half: u8 = node.value / 2;
    return if (half > 0) .{ half, half } else null;
}

fn sum(_: *anyopaque, x: u8, y: u8, _: u8) anyerror!u8 {
    return x + y;
}
