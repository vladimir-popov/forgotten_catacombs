const std = @import("std");
const math = @import("math");
const p = @import("primitives.zig");

pub const Tree = math.BinaryTree.Node(p.Region);

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

    var alloc = arena.allocator();
    var splitter = Splitter{ .rand = rand, .min_rows = min_rows, .min_cols = min_cols };
    var root: *Tree = try alloc.create(Tree);
    root.* = .{ .value = region };
    try root.split(alloc, 0, splitter.handler());

    return root;
}

const Splitter = struct {
    rand: std.Random,
    min_rows: u8,
    min_cols: u8,

    fn split(ptr: *anyopaque, node: *Tree, depth: u8) anyerror!?struct { p.Region, p.Region } {
        const self: *Splitter = @ptrCast(@alignCast(ptr));
        return if (depth % 2 == 0)
            node.value.splitHorizontaly(self.rand, self.min_rows)
        else
            node.value.splitVerticaly(self.rand, self.min_cols);
    }

    fn handler(self: *Splitter) Tree.SplitHandler {
        return .{ .ptr = self, .split = split };
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
    try root.traverse(0, validate.bspNodeHandler());
}

/// Utility for test
const ValidateNodes = struct {
    min_rows: u8,
    min_cols: u8,

    fn bspNodeHandler(self: *ValidateNodes) Tree.TraverseHandler {
        return .{ .ptr = self, .handle = validate };
    }

    fn validate(ptr: *anyopaque, root: *Tree, depth: u8) anyerror!void {
        const self: *ValidateNodes = @ptrCast(@alignCast(ptr));

        expect(!root.value.lessThan(self.min_rows, self.min_cols)) catch |err| {
            std.debug.print("The root region {any} is less than {d}x{d}\n", .{ root.value, self.min_rows, self.min_cols });
            return err;
        };
        if (root.left) |left| {
            try self.validateChild("left", root, left, depth);
        }
        if (root.right) |right| {
            try self.validateChild("right", root, right, depth);
        }
    }

    fn validateChild(
        self: *ValidateNodes,
        name: []const u8,
        root: *Tree,
        node: *Tree,
        depth: u8,
    ) !void {
        expect(root.value.contains(node.value)) catch |err| {
            std.debug.print(
                "The {s} region {any} doesn't contained in the root {any} on the depth {d}\n",
                .{ name, node.value, root.value, depth },
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
