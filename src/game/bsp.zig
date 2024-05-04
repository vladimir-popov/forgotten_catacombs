const std = @import("std");
const math = @import("math");

const Region = math.Region;

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
) !*Node {
    const region = Region{ .r = 1, .c = 1, .rows = rows, .cols = cols };
    std.debug.assert(!region.lessThan(min_rows, min_cols));

    var alloc = arena.allocator();
    var root: *Node = try alloc.create(Node);
    root.* = .{ .region = region, .is_horizontal = true };
    try root.split(alloc, rand, min_rows, min_cols);

    return root;
}

pub const Node = struct {
    parent: ?*Node = null,
    first: ?*Node = null,
    second: ?*Node = null,
    region: Region,
    is_horizontal: bool,

    pub inline fn isLeaf(self: *const Node) bool {
        return self.first == null and self.second == null;
    }

    /// Splits recursively the node until it possible, or does nothing.
    fn split(
        self: *Node,
        alloc: std.mem.Allocator,
        rand: std.Random,
        min_rows: u8,
        min_cols: u8,
    ) !void {
        std.debug.assert(self.first == null);
        std.debug.assert(self.second == null);

        const maybe_regions = if (self.is_horizontal)
            self.region.splitVerticaly(rand, min_cols)
        else
            self.region.splitHorizontaly(rand, min_rows);

        if (maybe_regions) |regions| {
            self.first = try alloc.create(Node);
            self.first.?.* = Node{
                .parent = self,
                .region = regions[0],
                .is_horizontal = !self.is_horizontal,
            };
            try self.first.?.split(alloc, rand, min_rows, min_cols);

            self.second = try alloc.create(Node);
            self.second.?.* = Node{
                .parent = self,
                .region = regions[1],
                .is_horizontal = !self.is_horizontal,
            };
            try self.second.?.split(alloc, rand, min_rows, min_cols);
        }
    }

    /// Traverse all nodes of this tree and pass them to the callback.
    pub fn traverse(self: *Node, init_depth: u8, handler: TraverseHandler) !void {
        try handler.handle(handler.ptr, self, init_depth);
        if (self.first) |first| {
            try traverse(first, init_depth + 1, handler);
        }
        if (self.second) |second| {
            try traverse(second, init_depth + 1, handler);
        }
    }
};

pub const TraverseHandler = struct {
    ptr: *anyopaque,
    /// ptr - pointer to the context of the handler
    /// node - the current node of the tree
    /// depth - the current depth
    handle: *const fn (ptr: *anyopaque, node: *Node, depth: u8) anyerror!void,
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

    fn bspNodeHandler(self: *ValidateNodes) Node.TraverseHandler {
        return .{ .ptr = self, .handle = validate };
    }

    fn validate(ptr: *anyopaque, root: *Node, depth: u8) anyerror!void {
        const self: *ValidateNodes = @ptrCast(@alignCast(ptr));

        expect(!root.region.lessThan(self.min_rows, self.min_cols)) catch |err| {
            std.debug.print("The root region {any} is less than {d}x{d}\n", .{ root.region, self.min_rows, self.min_cols });
            return err;
        };
        if (root.first) |first| {
            try self.validateChild("first", root, first, depth);
        }
        if (root.second) |second| {
            try self.validateChild("second", root, second, depth);
        }
    }

    fn validateChild(
        self: *ValidateNodes,
        name: []const u8,
        root: *Node,
        node: *Node,
        depth: u8,
    ) !void {
        expect(root.region.contains(node.region)) catch |err| {
            std.debug.print(
                "The {s} region {any} doesn't contained in the root {any} on the depth {d}",
                .{ name, node.region, root.region, depth },
            );
            return err;
        };
        expect(!root.region.lessThan(self.min_rows, self.min_cols)) catch |err| {
            std.debug.print("The {s} region {any} of the root {any} is less than {d}x{d}\n", .{
                name,
                node.region,
                root.region,
                self.min_rows,
                self.min_cols,
            });
            return err;
        };
    }
};
