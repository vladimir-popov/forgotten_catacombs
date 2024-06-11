const std = @import("std");

/// The Node of the BinaryTree.
pub fn Node(comptime V: type) type {
    return struct {
        const NodeV = @This();

        parent: ?*NodeV = null,
        left: ?*NodeV = null,
        right: ?*NodeV = null,
        value: V,
        lessThan: *const fn (x: V, y: V) bool,

        /// Creates a single root node of the binary tree.
        pub fn root(
            arena: *std.heap.ArenaAllocator,
            value: V,
            lessThan: *const fn (x: V, y: V) bool,
        ) !*Node(V) {
            const node = try arena.allocator().create(NodeV);
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
            arena: *std.heap.ArenaAllocator,
            splitter: SplitHandler,
        ) !void {
            std.debug.assert(self.left == null);
            std.debug.assert(self.right == null);
            var node: *NodeV = self;
            var another: ?*NodeV = null;
            while (true) {
                const maybe_values = try splitter.split(splitter.ptr, node);
                if (maybe_values) |values| {
                    node.left = try arena.allocator().create(NodeV);
                    node.left.?.* = NodeV{
                        .parent = node,
                        .lessThan = node.lessThan,
                        .value = values[0],
                    };
                    node.right = try arena.allocator().create(NodeV);
                    node.right.?.* = NodeV{
                        .parent = node,
                        .lessThan = node.lessThan,
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

        pub fn add(self: *NodeV, arena: *std.heap.ArenaAllocator, value: V) !void {
            if (self.lessThan(self.value, value)) {
                if (self.right) |right| {
                    try right.add(arena, value);
                } else {
                    self.right = try arena.allocator().create(NodeV);
                    self.right.?.* = NodeV{
                        .parent = self,
                        .lessThan = self.lessThan,
                        .value = value,
                    };
                }
            } else {
                if (self.left) |left| {
                    try left.add(arena, value);
                } else {
                    self.left = try arena.allocator().create(NodeV);
                    self.left.?.* = NodeV{
                        .parent = self,
                        .lessThan = self.lessThan,
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

        /// Folds the tree by passing values from the paired leafs to the handler,
        /// and modifies the parent of the leafs setting the value returned from the handler.
        /// Note, that only values from paired leafs are used.  Values of all other nodes are ignored,
        /// and replaces by the handler result.
        pub fn foldModify(self: *NodeV, alloc: std.mem.Allocator, handler: FoldHandler) !V {
            var stack = std.ArrayList(struct { *NodeV, *NodeV }).init(alloc);
            defer stack.deinit();
            var stack_prev_size: usize = 0;
            if (self.left orelse self.right == null) {
                return self.value;
            }
            try stack.append(.{ self.left.?, self.right.? });
            while (stack.getLastOrNull()) |nodes| {
                // if the pair is not leafs
                if (stack.items.len > stack_prev_size) {
                    stack_prev_size = stack.items.len;
                    inline for (0..2) |i| {
                        if (nodes[i].left) |left| {
                            if (nodes[i].right) |right| {
                                try stack.append(.{ left, right });
                            } else {
                                nodes[i].value = left.value;
                            }
                        } else {
                            if (nodes[i].right) |right| {
                                nodes[i].value = right.value;
                            }
                        }
                    }
                } else {
                    _ = stack.pop();
                    stack_prev_size = if (stack.items.len > 1) stack.items.len - 2 else 0;
                    nodes[0].parent.?.value = try handler.combine(handler.ptr, nodes[0].value, nodes[1].value);
                    nodes[0].parent.?.left = null;
                    nodes[0].parent.?.right = null;
                }
            }
            return self.value;
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
            combine: *const fn (ptr: *anyopaque, left_value: V, right_value: V) anyerror!V,
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
    var tree = try Node(u8).root(&arena, 8, compareU8);

    // when:
    try tree.split(&arena, divider);
    const result = try tree.foldModify(alloc, summator);

    // then:
    try std.testing.expectEqual(8, result);
}

test "add/traverse" {
    // given:
    const TraverseValidate = struct {
        const Self = @This();

        actual_values: []u8,
        idx: u8,

        fn handler(self: *Self) Node(u8).TraverseHandler {
            return .{ .ptr = self, .handle = accumulate_actual };
        }

        fn accumulate_actual(ptr: *anyopaque, node: *Node(u8)) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            // then:
            self.actual_values[self.idx] = node.value;
            self.idx += 1;
        }
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    //          3
    //      1       5
    //        2   4   6
    var tree = try Node(u8).root(&arena, 3, compareU8);
    try tree.add(&arena, 1);
    try tree.add(&arena, 2);
    try tree.add(&arena, 5);
    try tree.add(&arena, 4);
    try tree.add(&arena, 6);

    const expected_values = [_]u8{ 1, 2, 3, 4, 5, 6 };

    var actual_values = [_]u8{ 0, 0, 0, 0, 0, 0 };

    var validation = TraverseValidate{
        .actual_values = &actual_values,
        .idx = 0,
    };

    // when:
    try tree.traverse(arena.allocator(), validation.handler());

    // then:
    std.mem.sort(u8, &actual_values, {}, lessThanU8);
    try std.testing.expectEqualSlices(u8, &expected_values, &actual_values);
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

fn sum(_: *anyopaque, x: u8, y: u8) anyerror!u8 {
    return x + y;
}
