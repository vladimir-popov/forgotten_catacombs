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

const log = std.log.scoped(.bsp_generator);

const BspDungeonGenerator = @This();

/// The minimal rows count in the final region after BSP splitting
region_min_rows: u8 = 10,
/// The minimal columns count in the final region after BSP splitting
region_min_cols: u8 = 20,
/// Minimal scale rate to prevent too small rooms.
/// The small values make the dungeon looked more random.
min_scale: f16 = 0.6,
/// This is rows/cols ratio of the square.
/// In case of ascii graphics it's not 1.0
square_ratio: f16 = 0.4,

/// Creates the dungeon with BSP algorithm.
pub fn generateDungeon(
    self: BspDungeonGenerator,
    alloc: std.mem.Allocator,
    rand: std.Random,
    dungeon: *Dungeon,
) !void {
    // this arena is used to build a BSP tree, which can be destroyed
    // right after completing the dungeon.
    var bsp_arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = bsp_arena.deinit();

    // BSP helps to mark regions for rooms without intersections
    const root = try BspTree.build(
        &bsp_arena,
        rand,
        Dungeon.ROWS,
        Dungeon.COLS,
        .{ .min_rows = self.region_min_rows, .min_cols = self.region_min_cols, .square_ratio = self.square_ratio },
    );

    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{
        .generator = &self,
        .dungeon = dungeon,
        .rand = rand,
    };
    try root.traverse(&bsp_arena, createRooms.handler());
    log.debug("The rooms has been created", .{});

    // fold the BSP tree and binds nodes with the same parent:
    var createPassages: CreatePassageBetweenRegions = .{ .dungeon = dungeon, .alloc = alloc, .rand = rand };
    _ = try root.foldModify(&bsp_arena, createPassages.handler());
    log.debug("The passages has been created", .{});
}

const TraverseAndCreateRooms = struct {
    generator: *const BspDungeonGenerator,
    dungeon: *Dungeon,
    rand: std.Random,

    fn handler(self: *TraverseAndCreateRooms) BspTree.Node.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *BspTree.Node) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        const region_for_room = try self.generator.createRandomRegionInside(node.value, self.rand);
        try self.dungeon.generateAndAddRoom(self.rand, region_for_room);
    }
};

const CreatePassageBetweenRegions = struct {
    dungeon: *Dungeon,
    alloc: std.mem.Allocator,
    rand: std.Random,

    fn handler(self: *CreatePassageBetweenRegions) BspTree.Node.FoldHandler {
        return .{ .ptr = self, .combine = combine };
    }

    fn combine(ptr: *anyopaque, left: p.Region, right: p.Region) !p.Region {
        const self: *CreatePassageBetweenRegions = @ptrCast(@alignCast(ptr));
        log.debug("Creating passage between {any} and {any}", .{ left, right });
        return try self.dungeon.createAndAddPassageBetweenRegions(self.rand, left, right);
    }
};

/// Creates a smaller region inside the passed with random padding.
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
                self.region_min_rows,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.cols)) * self.square_ratio))),
            );
        } else {
            room.cols = @max(
                self.region_min_cols,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.rows)) / self.square_ratio))),
            );
        }
    }
    var scale: f16 = @floatFromInt(1 + rand.uintAtMost(u16, room.area() - self.minArea()));
    scale = scale / @as(f16, @floatFromInt(room.area()));
    scale = @max(self.min_scale, scale);
    room.scale(scale, scale);
    return room;
}

/// Minimal area of the room
inline fn minArea(self: BspDungeonGenerator) u8 {
    return self.region_min_rows * self.region_min_cols;
}
