//! The implementation of the dungeon generator with BSP algorithm.
//! It splits recurrently the dungeon region for smaller regions,
//! than creates the region for the room inside the splitted regions.
//!
//! Read more here:
//! <a href="https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation">
//! Basic_BSP_Dungeon_generation
//! </a>
const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const BspTree = @import("BspTree.zig");
const Catacomb = @import("Catacomb.zig");

const log = std.log.scoped(.bsp_generator);

pub const rows = 3 * g.DISPLAY_ROWS;
pub const cols = 3 * g.DISPLAY_COLS;

const Options = struct {
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

    /// Minimal area of the room
    inline fn minArea(opts: @This()) u16 {
        return opts.region_min_rows *| opts.region_min_cols;
    }
};

/// Creates the dungeon with BSP algorithm.
pub fn generateDungeon(
    arena: *std.heap.ArenaAllocator,
    init_seed: u64,
    opts: Options,
) !d.Dungeon {
    var prng = std.Random.DefaultPrng.init(init_seed);
    const rand = prng.random();

    // this arena is used to build a BSP tree, which can be destroyed
    // right after completing the dungeon.
    var bsp_arena = std.heap.ArenaAllocator.init(arena.allocator());
    defer _ = bsp_arena.deinit();

    // BSP helps to mark regions for rooms without intersections
    const root = try BspTree.build(
        &bsp_arena,
        rand,
        // g.DUNGEON_ROWS,
        // g.DUNGEON_COLS,
        rows,
        cols,
        .{ .min_rows = opts.region_min_rows, .min_cols = opts.region_min_cols, .square_ratio = opts.square_ratio },
    );

    const catacomb = try arena.allocator().create(Catacomb);
    catacomb.* = try Catacomb.init(arena);
    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{
        .dungeon = catacomb,
        .rand = rand,
        .opts = opts,
    };
    try root.traverse(&bsp_arena, createRooms.handler());
    log.debug("The rooms have been created", .{});

    // fold the BSP tree and binds nodes with the same parent:
    var createPassages: CreatePassageBetweenRegions = .{
        .dungeon = catacomb,
        .alloc = arena.allocator(),
        .rand = rand,
    };
    _ = try root.foldModify(&bsp_arena, createPassages.handler());
    log.debug("The passages have been created", .{});

    catacomb.entrance = (try catacomb.firstRoom()).randomPlace(rand);
    catacomb.exit = (try catacomb.lastRoom()).randomPlace(rand);

    return catacomb.dungeon(init_seed);
}

const TraverseAndCreateRooms = struct {
    dungeon: *Catacomb,
    rand: std.Random,
    opts: Options,

    fn handler(self: *TraverseAndCreateRooms) BspTree.Node.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *BspTree.Node) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        const region_for_room = try createRandomRegionInside(node.value, self.rand, self.opts);
        try self.dungeon.generateAndAddRoom(region_for_room);
    }
};

const CreatePassageBetweenRegions = struct {
    dungeon: *Catacomb,
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
fn createRandomRegionInside(region: p.Region, rand: std.Random, opts: Options) !p.Region {
    var room: p.Region = region;
    if (!std.math.approxEqAbs(f16, opts.square_ratio, region.ratio(), 0.1)) {
        // make the region 'more square'
        if (region.ratio() > opts.square_ratio) {
            room.rows = @max(
                opts.region_min_rows,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.cols)) * opts.square_ratio))),
            );
        } else {
            room.cols = @max(
                opts.region_min_cols,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.rows)) / opts.square_ratio))),
            );
        }
    }
    var scale: f16 = @floatFromInt(1 + rand.uintAtMost(u16, room.area() - opts.minArea()));
    scale = scale / @as(f16, @floatFromInt(room.area()));
    scale = @max(opts.min_scale, scale);
    room.scale(scale, scale);
    return room;
}
