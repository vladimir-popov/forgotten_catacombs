const std = @import("std");
const bsp = @import("bsp.zig");
const p = @import("primitives.zig");
const RoomGenerator = @import("RoomGenerator.zig");
pub const Walls = @import("Walls.zig");
pub const Passage = @import("Passage.zig");

/// The dungeon. Contains walls, doors, rooms and passages of the level.
const Dungeon = @This();

const log = std.log.scoped(.dungeon);

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
pub fn initEmpty(alloc: std.mem.Allocator, rows: u8, cols: u8) !Dungeon {
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

pub inline fn getRegion(self: Dungeon) p.Region {
    return .{ .top_left = .{ .row = 1, .col = 1 }, .rows = self.rows, .cols = self.cols };
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
        const left_region_door = self.findPlaceForDoorInRegionRnd(rand, x, .right) orelse return Error.NoSpaceForDoor;
        const right_region_door = self.findPlaceForDoorInRegionRnd(rand, y, .left) orelse return Error.NoSpaceForDoor;
        passage = try Passage.create(alloc, rand, left_region_door, right_region_door, &self.walls);
    } else {
        const top_region_door = self.findPlaceForDoorInRegionRnd(rand, x, .bottom) orelse return Error.NoSpaceForDoor;
        const bottom_region_door = self.findPlaceForDoorInRegionRnd(rand, y, .top) orelse return Error.NoSpaceForDoor;
        passage = try Passage.create(alloc, rand, top_region_door, bottom_region_door, &self.walls);
    }
    try self.passages.append(passage);
    try self.doors.put(passage.corners.items[0], rand.boolean());
    try self.doors.put(passage.corners.items[passage.corners.items.len - 1], rand.boolean());
    return x.unionWith(y);
}

fn findPlaceForDoorInRegionRnd(self: Dungeon, rand: std.Random, region: p.Region, side: p.Side) ?p.Point {
    const place = switch (side) {
        .top => p.Point{
            .row = region.top_left.row,
            .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRight().col),
        },
        .bottom => p.Point{
            .row = region.bottomRight().row,
            .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRight().col),
        },
        .left => p.Point{
            .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRight().row),
            .col = region.top_left.col,
        },
        .right => p.Point{
            .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRight().row),
            .col = region.bottomRight().col,
        },
    };
    log.debug(
        "The point to start search of a place for the door r:{d} c:{d} in the {any} from the {s} side\n",
        .{ place.row, place.col, region, @tagName(side) },
    );
    if (self.findEmptyPlaceInDirection(side.opposite(), place, region)) |result| {
        // move back to the wall:
        return result.movedTo(side);
    }
    // try to find in the different parts of the region:
    var new_region: ?p.Region = null;
    if (side.isHorizontal()) {
        new_region = if (rand.boolean())
            region.cutHorizontallyTo(place.row) orelse region.cutHorizontallyAfter(place.row)
        else
            region.cutHorizontallyAfter(place.row) orelse region.cutHorizontallyTo(place.row);
    } else {
        new_region = if (rand.boolean())
            region.cutVerticallyTo(place.col) orelse region.cutVerticallyAfter(place.col)
        else
            region.cutVerticallyAfter(place.col) orelse region.cutVerticallyTo(place.col);
    }
    if (new_region) |reg| {
        return self.findPlaceForDoorInRegionRnd(rand, reg, side);
    } else {
        return null;
    }
}

/// Looks for an empty place **inside** a room or a passage in the `region`.
/// Starting from the `start`, moves to the `direction`.
/// Returns the found place or null.
fn findEmptyPlaceInDirection(self: Dungeon, direction: p.Side, start: p.Point, region: p.Region) ?p.Point {
    var place = start;
    var cross_the_wall: bool = false;
    blk: while (region.containsPoint(place)) {
        const is_wall = self.walls.isWall(place.row, place.col);
        if (is_wall) {
            cross_the_wall = true;
        } else {
            if (cross_the_wall) {
                break :blk;
            }
        }
        place.move(direction);
    }
    if (region.containsPoint(place)) {
        return place;
    } else {
        return null;
    }
}

inline fn contains(self: Dungeon, point: p.Point) bool {
    return point.row > 0 and point.row <= self.rows and point.col > 0 and point.col <= self.cols;
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

    var dungeon = try Dungeon.initEmpty(alloc, rows, cols);
    // rooms generator to fill regions
    var room_gen = RoomGenerator.SimpleRoomGenerator{ .rand = rand };
    // BSP helps to mark regions for rooms without intersections
    const root = try bsp.buildTree(&arena, rand, rows, cols, 8, 15);
    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{ .generator = room_gen.generator(), .dungeon = &dungeon };
    try root.traverse(createRooms.handler());
    // fold the BSP tree and binds nodes with the same parent:
    var bindRooms: FoldAndBind = .{
        .generator = room_gen.generator(),
        .dungeon = &dungeon,
        .alloc = alloc,
        .rand = rand,
    };
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

test "find an empty place inside the room in the region from right to left" {
    // given:
    const str =
        \\####.
        \\#..#.
        \\#..#.
        \\####.
    ;
    var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
    defer dungeon.deinit();
    try dungeon.walls.parse(str);

    // when:
    const expected = dungeon.findEmptyPlaceInDirection(
        .left,
        p.Point{ .row = 2, .col = 5 },
        dungeon.getRegion(),
    );
    const unexpected = dungeon.findEmptyPlaceInDirection(
        .left,
        p.Point{ .row = 1, .col = 5 },
        dungeon.getRegion(),
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 3 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find an empty place inside the room in the region from bottom to top" {
    // given:
    const str =
        \\####.
        \\#..#.
        \\#..#.
        \\####.
    ;
    var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
    defer dungeon.deinit();
    try dungeon.walls.parse(str);

    // when:
    const expected = dungeon.findEmptyPlaceInDirection(
        .bottom,
        p.Point{ .row = 4, .col = 2 },
        dungeon.getRegion(),
    );
    const unexpected = dungeon.findEmptyPlaceInDirection(
        .bottom,
        p.Point{ .row = 4, .col = 1 },
        dungeon.getRegion(),
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 3, .col = 2 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find a random place for door" {
    // given:
    const str =
        \\####.
        \\#..#.
        \\#..#.
        \\####.
    ;
    const rand = std.crypto.random;
    var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
    defer dungeon.deinit();
    try dungeon.walls.parse(str);
    const region: p.Region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_right = dungeon.findPlaceForDoorInRegionRnd(rand, region, .right).?;
    // const place_bottom = try dungeon.findPlaceForDoorRnd(rand, region, .bottom);

    // then:
    try std.testing.expectEqual(4, place_right.col);
    try std.testing.expect(2 <= place_right.row and place_right.row <= 3);
    // and
    // try std.testing.expectEqual(4, place_bottom.row);
    // try std.testing.expect(2 <= place_bottom.col and place_bottom.col <= 3);
}

test {
    std.testing.refAllDecls(Dungeon);
}
