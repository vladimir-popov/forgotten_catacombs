const std = @import("std");
const bsp = @import("bsp.zig");
const p = @import("primitives.zig");

const RoomGenerator = @import("RoomGenerator.zig");
const Rooms = @import("Rooms.zig");
pub const Room = Rooms.Room;
const Passages = @import("Passages.zig");
const Passage = Passages.Passage;
pub const Walls = @import("Walls.zig");

const Error = error{NoSpaceForDoor};

/// The dungeon. Contains walls, doors, rooms and passages of the level.
const Dungeon = @This();

alloc: std.mem.Allocator,
rand: std.Random,
rows: u8,
cols: u8,
walls: Walls,
rooms: Rooms,
passages: Passages,

pub fn initEmpty(alloc: std.mem.Allocator, rand: std.Random, rows: u8, cols: u8) !Dungeon {
    return .{
        .alloc = alloc,
        .rand = rand,
        .rows = rows,
        .cols = cols,
        .walls = try Walls.initEmpty(alloc, rows, cols),
        .rooms = try Rooms.init(alloc),
        .passages = try Passages.init(alloc),
    };
}

pub fn deinit(self: Dungeon) void {
    self.walls.deinit();
    self.rooms.deinit();
    self.passages.deinit();
}

fn createRoom(self: *Dungeon, generator: RoomGenerator, region: p.Region) !void {
    const room = try generator.createRoom(&self.walls, region);
    try self.rooms.add(room);
}

fn createPassageBetween(self: *Dungeon, x: p.Region, y: p.Region, is_horizontal: bool) !p.Region {
    if (is_horizontal) {
        const left_region_door = try self.createDoor(x, .right, self.rand);
        const right_region_door = try self.createDoor(y, .left, self.rand);
        try self.passages.add(try Passage.create(self.alloc, left_region_door, right_region_door));
    } else {
        const top_region_door = try self.createDoor(x, .bottom, self.rand);
        const bottom_region_door = try self.createDoor(y, .top, self.rand);
        try self.passages.add(try Passage.create(self.alloc, top_region_door, bottom_region_door));
    }
    return x.unionWith(y);
}

fn createDoor(self: *Dungeon, region: p.Region, side: p.Side, rand: std.Random) Error!p.Point {
    // choose a room more frequently than a passage
    if (rand.uintAtMost(u8, 3) < 3) {
        if (self.createDoorInRoom(region, side, rand)) |door| {
            return door;
        } else if (self.createDoorInPassage(region, rand)) |door| {
            return door;
        }
    } else {
        if (self.createDoorInPassage(region, rand)) |door| {
            return door;
        } else if (self.createDoorInRoom(region, side, rand)) |door| {
            return door;
        }
    }
    return Error.NoSpaceForDoor;
}

fn createDoorInRoom(self: *Dungeon, region: p.Region, side: p.Side, rand: std.Random) ?p.Point {
    const rooms = self.rooms.findInside(region);
    if (rooms.len > 0) {
        const idx = rand.uintLessThan(u8, @intCast(rooms.len));
        return rooms[idx].createDoor(side, rand);
    } else {
        return null;
    }
}

fn createDoorInPassage(self: *Dungeon, region: p.Region, rand: std.Random) ?p.Point {
    const passages = self.passages.findInside(region);
    if (passages.len > 0) {
        const idx = rand.uintLessThan(u8, @intCast(passages.len));
        return try passages[idx].createDoor(rand);
    } else {
        return null;
    }
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

    var dungeon = try Dungeon.initEmpty(alloc, rand, rows, cols);
    // rooms generator to fill regions
    var room_gen = RoomGenerator.SimpleRoomGenerator{ .rand = rand };
    // BSP helps to mark regions for rooms without intersections
    const root = try bsp.buildTree(&arena, rand, rows, cols, 8, 15);
    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{ .generator = room_gen.generator(), .dungeon = &dungeon };
    try root.traverse(createRooms.handler());
    // fold the BSP tree and binds node with common parent
    var bindRooms: FoldAndBind = .{ .generator = room_gen.generator(), .dungeon = &dungeon };
    _ = try root.fold(bindRooms.handler());
    return dungeon;
}

const TraverseAndCreateRooms = struct {
    generator: RoomGenerator,
    dungeon: *Dungeon,

    fn handler(self: *TraverseAndCreateRooms) bsp.Tree.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *bsp.Tree) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        try self.dungeon.createRoom(self.generator, node.value);
    }
};

const FoldAndBind = struct {
    generator: RoomGenerator,
    dungeon: *Dungeon,

    fn handler(self: *FoldAndBind) bsp.Tree.FoldHandler {
        return .{ .ptr = self, .combine = FoldAndBind.bindRegions };
    }

    fn bindRegions(ptr: *anyopaque, x: p.Region, y: p.Region, depth: u8) anyerror!p.Region {
        const self: *FoldAndBind = @ptrCast(@alignCast(ptr));
        return try self.dungeon.createPassageBetween(x, y, (depth % 2 == 0));
    }
};
