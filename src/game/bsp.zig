const std = @import("std");
const Walls = @import("components.zig").Level.Walls;

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

pub fn generateMap(
    alloc: std.mem.Allocator,
    rand: std.Random,
    rows: u8,
    cols: u8,
    min_rows: u8,
    min_cols: u8,
) !Walls {
    // arena is used to build a BSP tree, which can be destroyed
    // right after completing the map.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = arena.reset(.free_all);
    // BSP helps to mark regions for rooms without intersections
    const root = try BSP.buildTree(&arena, rand, rows, cols, min_rows, min_cols);
    // the generator is about filling by walls the regions marked with BSP
    var generator = SimpleRoomGenerator{ .rand = rand, .walls = try Walls.initEmpty(alloc, rows, cols) };
    try root.traverse(0, generator.bspNodeHandler());
    return generator.walls;
}

const SimpleRoomGenerator = struct {
    const Self = @This();

    rand: std.Random,
    walls: Walls,

    fn bspNodeHandler(self: *Self) BSP.TraverseCallback {
        return .{ .ptr = self, .handle = handleNode };
    }

    fn handleNode(ptr: *anyopaque, node: *BSP, _: u8) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *Self = @ptrCast(@alignCast(ptr));
        try self.generateRoom(node.region);
    }

    fn generateRoom(self: *Self, region: Region) !void {
        const margin: u8 = 4;
        var reg = region;
        reg.r += margin;
        reg.c += margin;
        reg.rows -= margin;
        reg.cols -= margin;
        for (reg.r..(reg.r + reg.rows)) |i| {
            const r: u8 = @intCast(i);
            if (r == reg.r or r == (reg.r + reg.rows - 1)) {
                self.walls.setWalls(r, reg.c, reg.cols);
            } else {
                self.walls.setWall(r, reg.c);
                self.walls.setWall(r, reg.c + reg.cols - 1);
            }
        }
    }
};

/// The region on the map in which some room can be generated
const Region = struct {
    /// Top left corner row. Begins from 1.
    r: u8,
    /// Top left corner column. Begins from 1.
    c: u8,
    /// The count of rows in this region.
    rows: u8,
    /// The count of columns in this region.
    cols: u8,

    /// Splits this region vertically to two parts with no less than `min` columns in each.
    /// Returns null if splitting is impossible.
    fn splitVerticaly(self: Region, rand: std.Random, min: u8) ?struct { Region, Region } {
        if (split(rand, self.cols, min)) |middle| {
            return .{
                Region{ .r = self.r, .c = self.c, .rows = self.rows, .cols = middle },
                Region{ .r = self.r, .c = self.c + middle, .rows = self.rows, .cols = self.cols - middle },
            };
        } else {
            return null;
        }
    }

    /// Splits this region horizontally to two parts with no less than `min` rows in each.
    /// Returns null if splitting is impossible.
    fn splitHorizontaly(self: Region, rand: std.Random, min: u8) ?struct { Region, Region } {
        if (split(rand, self.rows, min)) |middle| {
            return .{
                Region{ .r = self.r, .c = self.c, .rows = middle, .cols = self.cols },
                Region{ .r = self.r + middle, .c = self.c, .rows = self.rows - middle, .cols = self.cols },
            };
        } else {
            return null;
        }
    }

    /// Randomly splits the `value` to two parts which are not less than `min`,
    /// or return null if it is impossible.
    inline fn split(rand: std.Random, value: u8, min: u8) ?u8 {
        return if (value > min * 2)
            min + rand.uintLessThan(u8, value - min * 2)
        else if (value == 2 * min)
            min
        else
            null;
    }

    /// Returns true if this region has less rows or columns than passed minimal
    /// values.
    inline fn lessThan(self: Region, min_rows: u8, min_cols: u8) bool {
        return self.rows < min_rows or self.cols < min_cols;
    }

    /// Returns the area of this region.
    inline fn area(self: Region) u16 {
        return self.rows * self.cols;
    }

    /// Returns true if the `other` region doesn't go beyond of this region.
    fn contains(self: Region, other: Region) bool {
        if (self.r > other.r or self.c > other.c)
            return false;
        if (self.r + self.rows < other.r + other.rows)
            return false;
        if (self.c + self.cols < other.c + other.cols)
            return false;
        return true;
    }
};

/// Basic BSP Dungeon generation
/// https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation
const BSP = struct {
    parent: ?*BSP = null,
    first: ?*BSP = null,
    second: ?*BSP = null,
    region: Region,
    is_horizontal: bool,

    inline fn isLeaf(self: *const BSP) bool {
        return self.first == null and self.second == null;
    }

    fn buildTree(
        arena: *std.heap.ArenaAllocator,
        rand: std.Random,
        rows: u8,
        cols: u8,
        min_rows: u8,
        min_cols: u8,
    ) !*BSP {
        const region = Region{ .r = 1, .c = 1, .rows = rows, .cols = cols };
        std.debug.assert(!region.lessThan(min_rows, min_cols));

        var alloc = arena.allocator();
        var root: *BSP = try alloc.create(BSP);
        root.* = .{ .region = region, .is_horizontal = true };
        try root.split(alloc, rand, min_rows, min_cols);

        return root;
    }

    /// Splits recursively the node until it possible, or does nothing.
    fn split(
        self: *BSP,
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
            self.first = try alloc.create(BSP);
            self.first.?.* = BSP{
                .parent = self,
                .region = regions[0],
                .is_horizontal = !self.is_horizontal,
            };
            try self.first.?.split(alloc, rand, min_rows, min_cols);

            self.second = try alloc.create(BSP);
            self.second.?.* = BSP{
                .parent = self,
                .region = regions[1],
                .is_horizontal = !self.is_horizontal,
            };
            try self.second.?.split(alloc, rand, min_rows, min_cols);
        }
    }

    const TraverseCallback = struct {
        ptr: *anyopaque,
        /// ptr - pointer to the context of the callback
        /// node - the current node of the tree
        /// depth - the current depth
        handle: *const fn (ptr: *anyopaque, node: *BSP, depth: u8) anyerror!void,
    };

    /// Traverse all nodes of this tree and pass them to the callback.
    fn traverse(self: *BSP, init_depth: u8, callback: TraverseCallback) !void {
        try callback.handle(callback.ptr, self, init_depth);
        if (self.first) |first| {
            try traverse(first, init_depth + 1, callback);
        }
        if (self.second) |second| {
            try traverse(second, init_depth + 1, callback);
        }
    }
};

test "build tree" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer _ = arena.reset(.free_all);
    var rand = std.Random.DefaultPrng.init(0);

    // when:
    const root = try BSP.buildTree(&arena, rand.random(), 9, 7, 3, 2);

    // then:
    var validate = ValidateNodes{ .min_rows = 2, .min_cols = 2 };
    try root.traverse(0, validate.bspNodeHandler());
}

/// Utility for test
const ValidateNodes = struct {
    min_rows: u8,
    min_cols: u8,

    fn bspNodeHandler(self: *ValidateNodes) BSP.TraverseCallback {
        return .{ .ptr = self, .handle = validate };
    }

    fn validate(ptr: *anyopaque, root: *BSP, depth: u8) anyerror!void {
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
        root: *BSP,
        node: *BSP,
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
