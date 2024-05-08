const std = @import("std");
const bsp = @import("bsp.zig");
const p = @import("primitives.zig");
const RoomGenerator = @import("RoomGenerator.zig");
pub const Walls = @import("Walls.zig");
pub const Passage = @import("Passage.zig");

/// The dungeon. Contains walls, doors, rooms and passages of the level.
const Dungeon = @This();

pub const Error = error{NoSpaceForDoor};

pub const Room = p.Region;

pub const Cell = enum { floor, wall, opened_door, closed_door };

pub const CellsIterator = struct {
    dungeon: *const Dungeon,
    current_place: p.Point,

    pub fn next(self: *CellsIterator) ?Cell {
        self.current_place.move(.right);
        if (self.current_place.col > self.dungeon.cols) {
            self.current_place.col = 1;
            self.current_place.row += 1;
        }
        if (self.current_place.row > self.dungeon.rows) {
            return null;
        }

        const is_wall =
            self.dungeon.walls.bitsets.items[self.current_place.row - 1].isSet(self.current_place.col - 1);
        if (is_wall) {
            return .wall;
        }
        if (self.dungeon.doors.getPtr(self.current_place)) |door| {
            return if (door.*) .closed_door else .opened_door;
        }
        return .floor;
    }
};

rows: u8,
cols: u8,
walls: Walls,
rooms: std.ArrayList(Room),
passages: std.ArrayList(Passage),
// true for closed doors
doors: std.AutoHashMap(p.Point, bool),

/// Initializes an empty dungeon with passed count of `rows` and `cols`.
pub fn init(alloc: std.mem.Allocator, rows: u8, cols: u8) !Dungeon {
    return .{
        .rows = rows,
        .cols = cols,
        .walls = try Walls.initEmpty(alloc, rows, cols),
        .rooms = std.ArrayList(Room).init(alloc),
        .passages = std.ArrayList(Passage).init(alloc),
        .doors = std.AutoHashMap(p.Point, bool).init(alloc),
    };
}

pub fn deinit(self: Dungeon) void {
    self.walls.deinit();
    self.rooms.deinit();
    self.passages.deinit();
}

pub fn cells(self: *const Dungeon) CellsIterator {
    return .{ .dungeon = self, .current_place = .{ .row = 1, .col = 0 } };
}

fn createRoom(self: *Dungeon, generator: RoomGenerator, region: p.Region) !void {
    const room = try generator.createRoom(&self.walls, region);
    try self.rooms.append(room);
}

fn createPassageBetween(
    self: *Dungeon,
    alloc: std.mem.Allocator,
    rand: std.Random,
    x: p.Region,
    y: p.Region,
    is_horizontal: bool,
) !p.Region {
    var passage: Passage = undefined;
    if (is_horizontal) {
        const left_region_door = self.findPlaceForDoor(rand, x, .right);
        const right_region_door = self.findPlaceForDoor(rand, y, .left);
        passage = try Passage.create(alloc, rand, left_region_door, right_region_door, &self.walls);
    } else {
        const top_region_door = self.findPlaceForDoor(rand, x, .bottom);
        const bottom_region_door = self.findPlaceForDoor(rand, y, .top);
        passage = try Passage.create(alloc, rand, top_region_door, bottom_region_door, &self.walls);
    }
    try self.passages.append(passage);
    try self.doors.put(passage.corners.items[0], rand.boolean());
    try self.doors.put(passage.corners.items[passage.corners.items.len - 1], rand.boolean());
    return x.unionWith(y);
}

fn findPlaceForDoor(self: Dungeon, rand: std.Random, region: p.Region, side: p.Side) p.Point {
    var point = switch (side) {
        .top => p.Point{
            .row = region.top_left.row,
            .col = rand.uintLessThan(u8, region.cols - 1) + region.top_left.col + 1,
        },
        .bottom => p.Point{
            .row = region.top_left.row + region.rows - 1,
            .col = rand.uintLessThan(u8, region.cols - 1) + region.top_left.col + 1,
        },
        .left => p.Point{
            .row = rand.uintLessThan(u8, region.rows - 1) + region.top_left.row + 1,
            .col = region.top_left.col,
        },
        .right => p.Point{
            .row = rand.uintLessThan(u8, region.rows - 1) + region.top_left.row + 1,
            .col = region.top_left.col + region.cols - 1,
        },
    };
    while (self.walls.isWall(point.row, point.col) and self.contains(point)) {
        point.move(side.opposite());
    }
    if (!self.contains(point))
        std.debug.panic("A place for the door was not found in {any} on {any}", .{ region, side });

    return point;
}

inline fn contains(self: Dungeon, point: p.Point) bool {
    return point.row < self.rows and point.col < self.cols;
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

    var dungeon = try Dungeon.init(alloc, rows, cols);
    // rooms generator to fill regions
    var room_gen = RoomGenerator.SimpleRoomGenerator{ .rand = rand };
    // BSP helps to mark regions for rooms without intersections
    const root = try bsp.buildTree(&arena, rand, rows, cols, 8, 15);
    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{ .generator = room_gen.generator(), .dungeon = &dungeon };
    try root.traverse(createRooms.handler());
    // fold the BSP tree and binds node with common parent
    // var bindRooms: FoldAndBind = .{
    //     .generator = room_gen.generator(),
    //     .dungeon = &dungeon,
    //     .alloc = alloc,
    //     .rand = rand,
    // };
    // _ = try root.fold(bindRooms.handler());
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
    alloc: std.mem.Allocator,
    rand: std.Random,

    fn handler(self: *FoldAndBind) bsp.Tree.FoldHandler {
        return .{ .ptr = self, .combine = FoldAndBind.bindRegions };
    }

    fn bindRegions(ptr: *anyopaque, x: p.Region, y: p.Region, depth: u8) anyerror!p.Region {
        const self: *FoldAndBind = @ptrCast(@alignCast(ptr));
        return try self.dungeon.createPassageBetween(self.alloc, self.rand, x, y, (depth % 2 == 0));
    }
};

test {
    std.testing.refAllDecls(Dungeon);
}
