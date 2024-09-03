//! Implementation of the dungeon generator with BSP algorithm.
//! https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation
const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

const BspTree = @import("BspTree.zig");
const Dungeon = @import("Dungeon.zig");
const DungeonBuilder = @import("DungeonBuilder.zig");

const BspDungeonGenerator = @This();

/// Minimal rows count in the room
min_rows: u8 = 5,
/// Minimal columns count in the room
min_cols: u8 = 5,
/// Minimal scale rate to prevent too small rooms
min_scale: f16 = 0.6,
/// This is rows/cols ratio of the square.
/// In case of ascii graphics it's not 1.0
square_ratio: f16 = 0.4,

/// Creates the dungeon with BSP algorithm.
pub fn generateDungeon(self: BspDungeonGenerator, alloc: std.mem.Allocator, seed: u64) !*Dungeon {
    var prng = std.Random.DefaultPrng.init(seed);
    // this arena is used to build a BSP tree, which can be destroyed
    // right after completing the dungeon.
    var bsp_arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = bsp_arena.deinit();

    const dungeon = try alloc.create(Dungeon);
    dungeon.* = try Dungeon.init(alloc, seed);

    // BSP helps to mark regions for rooms without intersections
    const root = try BspTree.build(&bsp_arena, prng.random(), Dungeon.Rows, Dungeon.Cols, .{});

    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{
        .generator = self,
        .builder = .{ .dungeon = dungeon },
        .rand = prng.random(),
    };
    try root.traverse(bsp_arena.allocator(), createRooms.handler());

    // fold the BSP tree and binds nodes with the same parent:
    var createPassages: CreatePassageBetweenRegions = .{ .dungeon = dungeon, .rand = prng.random() };
    _ = try root.foldModify(alloc, createPassages.handler());

    return dungeon;
}

const TraverseAndCreateRooms = struct {
    generator: BspDungeonGenerator,
    builder: DungeonBuilder,
    rand: std.Random,

    fn handler(self: *TraverseAndCreateRooms) BspTree.Node.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *BspTree.Node) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        const region_for_room = self.generator.createRandomRegionInside(node.value);
        try self.builder.generateAndAddRoom(self.rand, region_for_room);
    }
};

const CreatePassageBetweenRegions = struct {
    builder: *DungeonBuilder,
    rand: std.Random,

    fn handler(self: *CreatePassageBetweenRegions) BspTree.Node.FoldHandler {
        return .{ .ptr = self, .combine = combine };
    }

    fn combine(ptr: *anyopaque, left: *p.Region, right: *p.Region) !p.Region {
        const self: *CreatePassageBetweenRegions = @ptrCast(@alignCast(ptr));
        return try self.builder.createAndAddPassageBetweenRegions(self.rand, left, right);
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
    room.scale(@max(self.min_scale, scale));
    return room;
}

/// Minimal area of the room
inline fn minArea(self: BspDungeonGenerator) u8 {
    return self.min_rows * self.min_cols;
}
