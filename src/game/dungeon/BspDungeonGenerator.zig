//! The implementation of the dungeon generator with BSP algorithm.
//! It splits recurrently the dungeon region for smaller regions,
//! than creates the region for the room inside the splitted regions,
//! and invokes room factory to create the final room.
//!
//! Read more here:
//! <a href="https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation">
//! Basic_BSP_Dungeon_generation
//! </a>
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const BspTree = @import("BspTree.zig");
const Dungeon = @import("Dungeon.zig");
const DungeonBuilder = @import("DungeonBuilder.zig");
const DungeonGenerator = @import("DungeonGenerator.zig");

const BspDungeonGenerator = @This();

/// Used to create arena for BSP tree
alloc: std.mem.Allocator,
/// Minimal rows count in the room
min_rows: u8 = 5,
/// Minimal columns count in the room
min_cols: u8 = 5,
/// Minimal scale rate to prevent too small rooms
min_scale: f16 = 0.6,
/// This is rows/cols ratio of the square.
/// In case of ascii graphics it's not 1.0
square_ratio: f16 = 0.4,

pub fn generator(self: *BspDungeonGenerator) DungeonGenerator {
    return .{ .context = self, .generateFn = generateDungeon };
}

/// Creates the dungeon with BSP algorithm.
fn generateDungeon(
    ptr: *anyopaque,
    rand: std.Random,
    builder: DungeonBuilder,
) !void {
    const self: *BspDungeonGenerator = @ptrCast(@alignCast(ptr));
    // this arena is used to build a BSP tree, which can be destroyed
    // right after completing the dungeon.
    var bsp_arena = std.heap.ArenaAllocator.init(self.alloc);
    defer _ = bsp_arena.deinit();

    // BSP helps to mark regions for rooms without intersections
    const root = try BspTree.build(&bsp_arena, rand, Dungeon.ROWS, Dungeon.COLS, .{});

    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{
        .generator = self,
        .builder = builder,
        .rand = rand,
    };
    try root.traverse(bsp_arena.allocator(), createRooms.handler());

    // fold the BSP tree and binds nodes with the same parent:
    var createPassages: CreatePassageBetweenRegions = .{ .builder = builder, .alloc = self.alloc, .rand = rand };
    _ = try root.foldModify(bsp_arena.allocator(), createPassages.handler());
}

const TraverseAndCreateRooms = struct {
    generator: *const BspDungeonGenerator,
    builder: DungeonBuilder,
    rand: std.Random,

    fn handler(self: *TraverseAndCreateRooms) BspTree.Node.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *BspTree.Node) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        const region_for_room = try self.generator.createRandomRegionInside(node.value, self.rand);
        try self.builder.generateAndAddRoom(self.rand, region_for_room);
    }
};

const CreatePassageBetweenRegions = struct {
    builder: DungeonBuilder,
    alloc: std.mem.Allocator,
    rand: std.Random,

    fn handler(self: *CreatePassageBetweenRegions) BspTree.Node.FoldHandler {
        return .{ .ptr = self, .combine = combine };
    }

    fn combine(ptr: *anyopaque, left: p.Region, right: p.Region) !p.Region {
        const self: *CreatePassageBetweenRegions = @ptrCast(@alignCast(ptr));
        return try self.builder.createAndAddPassageBetweenRegions(self.alloc, self.rand, left, right);
    }
};

/// Creates smaller region inside the passed with random padding.
///
/// Example of the room inside the 7x7 region with padding 1
/// (the room's region includes the '#' cells):
///
///  ________
/// |       |
/// |       |
/// | ##### |
/// | #   # |
/// | ##### |
/// |       |
/// |       |
/// ---------
fn createRandomRegionInside(self: BspDungeonGenerator, region: p.Region, rand: std.Random) !p.Region {
    var room: p.Region = region;
    if (!std.math.approxEqAbs(f16, self.square_ratio, region.ratio(), 0.1)) {
        // make the region 'more square'
        if (region.ratio() > self.square_ratio) {
            room.rows = @max(
                self.min_rows,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.cols)) * self.square_ratio))),
            );
        } else {
            room.cols = @max(
                self.min_cols,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.rows)) / self.square_ratio))),
            );
        }
    }
    var scale: f16 = @floatFromInt(1 + rand.uintLessThan(u16, room.area() - self.minArea()));
    scale = scale / @as(f16, @floatFromInt(room.area()));
    scale = @max(self.min_scale, scale);
    room.scale(scale, scale);
    return room;
}

/// Minimal area of the room
inline fn minArea(self: BspDungeonGenerator) u8 {
    return self.min_rows * self.min_cols;
}
