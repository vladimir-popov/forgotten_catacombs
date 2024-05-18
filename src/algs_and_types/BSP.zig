const std = @import("std");
const p = @import("primitives.zig");
const BinaryTree = @import("BinaryTree.zig");

pub const Tree = BinaryTree.Node(p.Region);

/// Builds graph of regions splitting the original region with `rows` and `cols`
/// on smaller regions with minimum `min_rows` or `min_cols`. A region from any
/// node contains regions of its children.
///
/// To free memory with returned graph, the arena should be freed.
pub fn buildTree(
    arena: *std.heap.ArenaAllocator,
    rand: std.Random,
    rows: u8,
    cols: u8,
    min_rows: u8,
    min_cols: u8,
) !*Tree {
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols };
    std.debug.assert(!region.lessThan(min_rows, min_cols));

    const alloc = arena.allocator();
    var splitter = Splitter{ .rand = rand, .min_rows = min_rows, .min_cols = min_cols };
    var root: *Tree = try Tree.root(alloc, region, compare);
    try root.split(alloc, splitter.handler());

    return root;
}

fn compare(_: u8, _: p.Region, _: p.Region) i8 {
    return 0;
}

const Splitter = struct {
    rand: std.Random,
    min_rows: u8,
    min_cols: u8,

    fn handler(self: *Splitter) Tree.SplitHandler {
        return .{ .ptr = self, .split = split };
    }

    fn split(ptr: *anyopaque, node: *Tree) anyerror!?struct { p.Region, p.Region } {
        const self: *Splitter = @ptrCast(@alignCast(ptr));
        const region: p.Region = node.value;
        if (node.depth % 2 == 0) {
            if (divideRnd(self.rand, region.rows, self.min_rows)) |rows| {
                return region.splitHorizontally(rows);
            }
        } else {
            if (divideRnd(self.rand, region.cols, self.min_rows)) |cols| {
                return region.splitVertically(cols);
            }
        }
        return null;
    }

    /// Randomly divides the `value` to two parts which are not less than `min`,
    /// or return null if it is impossible.
    inline fn divideRnd(rand: std.Random, value: u8, min: u8) ?u8 {
        return if (value > min * 2)
            min + rand.uintLessThan(u8, value - min * 2)
        else if (value == 2 * min)
            min
        else
            null;
    }
};

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "build tree" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    var rand = std.Random.DefaultPrng.init(0);

    // when:
    const root = try buildTree(&arena, rand.random(), 9, 7, 3, 2);

    // then:
    var validate = ValidateNodes{ .min_rows = 2, .min_cols = 2 };
    try root.traverse(validate.bspNodeHandler());
}

/// Utility for test
const ValidateNodes = struct {
    min_rows: u8,
    min_cols: u8,

    fn bspNodeHandler(self: *ValidateNodes) Tree.TraverseHandler {
        return .{ .ptr = self, .handle = validate };
    }

    fn validate(ptr: *anyopaque, node: *Tree) anyerror!void {
        const self: *ValidateNodes = @ptrCast(@alignCast(ptr));

        expect(!node.value.lessThan(self.min_rows, self.min_cols)) catch |err| {
            std.debug.print("The root region {any} is less than {d}x{d}\n", .{ node.value, self.min_rows, self.min_cols });
            return err;
        };
        if (node.left) |left| {
            try self.validateChild("left", node, left);
        }
        if (node.right) |right| {
            try self.validateChild("right", node, right);
        }
    }

    fn validateChild(
        self: *ValidateNodes,
        name: []const u8,
        root: *Tree,
        node: *Tree,
    ) !void {
        expect(root.value.containsRegion(node.value)) catch |err| {
            std.debug.print(
                "The {s} region {any} doesn't contained in the root {any}\n",
                .{ name, node.value, root.value },
            );
            return err;
        };
        expect(!root.value.lessThan(self.min_rows, self.min_cols)) catch |err| {
            std.debug.print("The {s} region {any} of the root {any} is less than {d}x{d}\n", .{
                name,
                node.value,
                root.value,
                self.min_rows,
                self.min_cols,
            });
            return err;
        };
    }
};
