const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.bsp_tree);

pub const Node = GenericNode(p.Region);

pub const MinRegionSettings = struct {
    /// rows / cols ratio to keep regions looked as square:
    square_ratio: f16,
    min_rows: u8,
    min_cols: u8,
    split_with_gap: bool = false,

    fn validateRegion(self: MinRegionSettings, region: p.Region) void {
        if (region.rows < self.min_rows) {
            std.debug.panic("The {any} has less than {d} min rows.\n", .{
                region,
                self.min_rows,
            });
        }
        if (region.cols < self.min_cols) {
            std.debug.panic("The {any} has less than {d} min cols.\n", .{
                region,
                self.min_cols,
            });
        }
    }
};

/// Builds graph of regions splitting the original region with `rows` and `cols`
/// on smaller regions with minimum `min_rows` or `min_cols`. A region from any
/// node contains regions of its children.
///
/// To free memory with returned graph, the arena should be freed.
pub fn build(
    arena: *std.heap.ArenaAllocator,
    rand: std.Random,
    rows: u8,
    cols: u8,
    opts: MinRegionSettings,
) !*Node {
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols };
    opts.validateRegion(region);

    var splitter = Splitter{ .rand = rand, .opts = opts };
    var root: *Node = try Node.root(arena, region);
    try root.split(arena, splitter.handler());

    return root;
}

const Splitter = struct {
    rand: std.Random,
    opts: MinRegionSettings,

    fn handler(self: *Splitter) Node.SplitHandler {
        return .{ .ptr = self, .split = split };
    }

    fn split(ptr: *anyopaque, node: *GenericNode(p.Region)) anyerror!?struct { p.Region, p.Region } {
        const self: *Splitter = @ptrCast(@alignCast(ptr));

        const split_vertical = node.value.ratio() < self.opts.square_ratio;
        const gap: u8 = if (self.opts.split_with_gap) 1 else 0;
        if (split_vertical) {
            if (node.value.cols >= (2 * self.opts.min_cols + gap)) {
                const middle = self.rand.intRangeAtMost(
                    u8,
                    self.opts.min_cols,
                    node.value.cols - self.opts.min_cols,
                );
                log.debug(
                    "Split {any} vertically at {d} {s}",
                    .{ node.value, middle, if (self.opts.split_with_gap) "with gap" else "without gap" },
                );
                if (self.opts.split_with_gap)
                    return zip(node.value.croppedVerticallyTo(middle), node.value.croppedVerticallyAfter(middle))
                else
                    return node.value.splitVertically(middle);
            } else {
                log.debug(
                    "Stop splitting vertically, because of cols are not enough: {any} {any}",
                    .{ node.value, self.opts },
                );
            }
        } else {
            if (node.value.rows >= (2 * self.opts.min_rows + gap)) {
                const middle = self.rand.intRangeAtMost(u8, self.opts.min_rows, node.value.rows - self.opts.min_rows);
                log.debug(
                    "Split {any} horizontally at {d} {s}",
                    .{ node.value, middle, if (self.opts.split_with_gap) "with gap" else "without gap" },
                );
                if (self.opts.split_with_gap)
                    return zip(node.value.croppedHorizontallyTo(middle), node.value.croppedHorizontallyAfter(middle))
                else
                    return node.value.splitHorizontally(middle);
            } else {
                log.debug(
                    "Stop splitting horizontally, because of rows are not enough: {any} {any}",
                    .{ node.value, self.opts },
                );
            }
        }
        return null;
    }
};

fn zip(
    maybe_a: anytype,
    maybe_b: anytype,
) ?struct { @typeInfo(@TypeOf(maybe_a)).optional.child, @typeInfo(@TypeOf(maybe_b)).optional.child } {
    if (maybe_a) |a| if (maybe_b) |b| return .{ a, b };
    return null;
}

/// The Node of the Tree.
fn GenericNode(comptime V: type) type {
    return struct {
        const NodeV = @This();

        parent: ?*NodeV = null,
        left: ?*NodeV = null,
        right: ?*NodeV = null,
        value: V,

        /// Creates a single root node of the binary tree.
        pub fn root(
            arena: *std.heap.ArenaAllocator,
            value: V,
        ) !*NodeV {
            const node = try arena.allocator().create(NodeV);
            node.* = .{ .value = value };
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
            var stack = std.ArrayList(*NodeV).init(arena.allocator());
            try stack.append(self);
            while (stack.pop()) |node| {
                const maybe_values = try splitter.split(splitter.ptr, node);
                if (maybe_values) |values| {
                    log.debug("Splitted into regions: {any}", .{values});
                    node.left = try arena.allocator().create(NodeV);
                    node.left.?.* = NodeV{
                        .parent = node,
                        .value = values[0],
                    };
                    node.right = try arena.allocator().create(NodeV);
                    node.right.?.* = NodeV{
                        .parent = node,
                        .value = values[1],
                    };
                    try stack.append(node.right.?);
                    try stack.append(node.left.?);
                }
            }
        }

        pub fn add(
            self: *NodeV,
            arena: *std.heap.ArenaAllocator,
            value: V,
            lessThan: *const fn (x: V, y: V) bool,
        ) !void {
            if (lessThan(self.value, value)) {
                if (self.right) |right| {
                    try right.add(arena, value, lessThan);
                } else {
                    self.right = try arena.allocator().create(NodeV);
                    self.right.?.* = NodeV{
                        .parent = self,
                        .value = value,
                    };
                }
            } else {
                if (self.left) |left| {
                    try left.add(arena, value, lessThan);
                } else {
                    self.left = try arena.allocator().create(NodeV);
                    self.left.?.* = NodeV{
                        .parent = self,
                        .value = value,
                    };
                }
            }
        }

        /// Traverse all nodes of this tree in depth, and pass them to the callback.
        pub fn traverse(self: *NodeV, arena: *std.heap.ArenaAllocator, handler: TraverseHandler) !void {
            var stack = std.ArrayList(*NodeV).init(arena.allocator());
            try stack.append(self);
            while (stack.pop()) |node| {
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
        pub fn foldModify(self: *NodeV, arena: *std.heap.ArenaAllocator, handler: FoldHandler) !V {
            var stack = std.ArrayList(struct { *NodeV, *NodeV }).init(arena.allocator());
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
            combine: *const fn (ptr: *anyopaque, left: V, right: V) anyerror!V,
        };
    };
}

test "build tree" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var rand = std.Random.DefaultPrng.init(0);
    const opts: MinRegionSettings = .{ .min_rows = 2, .min_cols = 2, .square_ratio = 0.4 };

    // when:
    const root = try build(&arena, rand.random(), 9, 7, opts);

    // then:
    var validate = ValidateNodes{ .opts = opts };
    try root.traverse(&arena, validate.bspNodeHandler());
}

/// Utility for test
const ValidateNodes = struct {
    opts: MinRegionSettings,
    min_ratio: f16 = 0.2,

    fn bspNodeHandler(self: *ValidateNodes) Node.TraverseHandler {
        return .{ .ptr = self, .handle = validate };
    }

    fn validate(ptr: *anyopaque, node: *Node) anyerror!void {
        const self: *ValidateNodes = @ptrCast(@alignCast(ptr));

        try self.validateNode("root", null, node);
        if (node.left) |left| {
            try self.validateNode("left", node, left);
        }
        if (node.right) |right| {
            try self.validateNode("right", node, right);
        }
    }

    fn validateNode(
        self: *ValidateNodes,
        name: []const u8,
        root: ?*Node,
        node: *Node,
    ) !void {
        if (root) |rt| {
            std.testing.expect(rt.value.containsRegion(node.value)) catch |err| {
                std.debug.print(
                    "The {s} region {any} doesn't contained in the root {any}\n",
                    .{ name, node.value, rt.value },
                );
                return err;
            };
        }
        if (node.value.rows < self.opts.min_rows) {
            std.debug.print("The {s} {any} has less than {d} min rows.\n", .{
                name,
                node.value,
                self.opts.min_rows,
            });
            return error.TestUnexpectedResult;
        }
        if (node.value.cols < self.opts.min_cols) {
            std.debug.print("The {s} {any} has less than {d} min cols.\n", .{
                name,
                node.value,
                self.opts.min_cols,
            });
            return error.TestUnexpectedResult;
        }
        if (node.value.ratio() < self.min_ratio) {
            std.debug.print("The {s} {any} has lower ratio {d} than {d}.\n", .{
                name,
                node.value,
                node.value.ratio(),
                self.min_ratio,
            });
            return error.TestUnexpectedResult;
        }
    }
};

test "split/fold" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const divider = GenericNode(u8).SplitHandler{ .ptr = undefined, .split = divide };
    const summator = GenericNode(u8).FoldHandler{ .ptr = undefined, .combine = sum };
    var tree = try GenericNode(u8).root(&arena, 8);

    // when:
    try tree.split(&arena, divider);
    const result = try tree.foldModify(&arena, summator);

    // then:
    try std.testing.expectEqual(8, result);
}

test "add/traverse" {
    // given:
    const TraverseValidate = struct {
        const Self = @This();

        actual_values: []u8,
        idx: u8,

        fn handler(self: *Self) GenericNode(u8).TraverseHandler {
            return .{ .ptr = self, .handle = accumulate_actual };
        }

        fn accumulate_actual(ptr: *anyopaque, node: *GenericNode(u8)) !void {
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
    var tree = try GenericNode(u8).root(&arena, 3);
    try tree.add(&arena, 1, compareU8);
    try tree.add(&arena, 2, compareU8);
    try tree.add(&arena, 5, compareU8);
    try tree.add(&arena, 4, compareU8);
    try tree.add(&arena, 6, compareU8);

    const expected_values = [_]u8{ 1, 2, 3, 4, 5, 6 };

    var actual_values = [_]u8{ 0, 0, 0, 0, 0, 0 };

    var validation = TraverseValidate{
        .actual_values = &actual_values,
        .idx = 0,
    };

    // when:
    try tree.traverse(&arena, validation.handler());

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

fn divide(_: *anyopaque, node: *GenericNode(u8)) anyerror!?struct { u8, u8 } {
    const half: u8 = node.value / 2;
    return if (half > 0) .{ half, half } else null;
}

fn sum(_: *anyopaque, x: u8, y: u8) anyerror!u8 {
    return x + y;
}
