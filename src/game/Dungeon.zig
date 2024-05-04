/// The map of the level. Contains walls, doors, rooms and passages.
const std = @import("std");
const bsp = @import("bsp.zig");
const RoomGenerator = @import("RoomGenerator.zig");

const Dungeon = @This();
const Walls = std.ArrayList(std.DynamicBitSet);

pub const ROWS: u8 = 40;
pub const COLS: u8 = 80;

rows: u8,
cols: u8,
walls: Walls,

pub fn initEmpty(alloc: std.mem.Allocator, rows: u8, cols: u8) Dungeon {
    return .{ .walls = try initWalls(alloc, rows, cols), .rows = rows, .cols = cols };
}

fn initWalls(alloc: std.mem.Allocator, rows: u8, cols: u8) !Walls {
    var bitsets = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
    for (0..rows) |_| {
        const row = bitsets.addOneAssumeCapacity();
        row.* = try std.DynamicBitSet.initEmpty(alloc, cols);
    }
    return bitsets;
}

pub fn deinit(self: Dungeon) void {
    for (self.walls.items) |*row| {
        row.deinit();
    }
    self.walls.deinit();
}

pub fn hasWall(self: Dungeon, row: u8, col: u8) bool {
    if (row < 1 or row >= self.walls.items.len)
        return true;
    const walls_row = self.walls.items[row - 1];
    if (col < 1 or col >= walls_row.capacity())
        return true;
    return walls_row.isSet(col - 1);
}

pub fn setWall(self: *Dungeon, row: u8, col: u8) void {
    self.walls.items[row - 1].set(col - 1);
}

pub fn setWalls(self: *Dungeon, row: u8, from_col: u8, count: u8) void {
    self.walls.items[row - 1].setRangeValue(.{ .start = from_col - 1, .end = from_col + count - 1 }, true);
}

/// Basic BSP Dungeon generation
/// https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation
pub fn bspGenerate(
    alloc: std.mem.Allocator,
    rand: std.Random,
    rows: u8,
    cols: u8,
) !Dungeon {
    // arena is used to build a BSP tree, which can be destroyed
    // right after completing the map.
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = arena.deinit();

    var dungeon = Dungeon{ .rows = rows, .cols = cols, .walls = try initWalls(alloc, rows, cols) };
    // rooms generator to fill regions
    const rooms = RoomGenerator.simpleRooms();
    // BSP helps to mark regions for rooms without intersections
    const root = try bsp.buildTree(&arena, rand, rows, cols, 10, 10);
    // visit every BSP node and generate rooms in the leafs
    var bspNodeHandler: BspTraverseAndGenerate = .{ .rooms = rooms, .dungeon = &dungeon };
    try root.traverse(0, bspNodeHandler.handler());
    return dungeon;
}

const BspTraverseAndGenerate = struct {
    rooms: RoomGenerator,
    dungeon: *Dungeon,

    fn handler(self: *BspTraverseAndGenerate) bsp.TraverseHandler {
        return .{ .ptr = self, .handle = handleNode };
    }

    fn handleNode(ptr: *anyopaque, node: *bsp.Node, _: u8) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *BspTraverseAndGenerate = @ptrCast(@alignCast(ptr));
        try self.rooms.generateRoom(self.dungeon, node.region.r, node.region.c, node.region.rows, node.region.cols);
    }
};
