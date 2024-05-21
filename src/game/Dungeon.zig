const std = @import("std");
const builtin = @import("builtin");
const algs_and_types = @import("algs_and_types");

const bsp = algs_and_types.BSP;
const p = algs_and_types.primitives;

const log = std.log.scoped(.dungeon);

pub const Error = error{NoSpaceForDoor};

pub const Room = p.Region;

/// The passage is a collection of turns
pub const Passage = std.ArrayList(p.Point);

pub const Cell = enum { nothing, floor, wall, opened_door, closed_door };

pub fn Dungeon(comptime rows_count: u8, cols_count: u8) type {
    return struct {
        /// The dungeon. Contains walls, doors, rooms and passages of the level.
        const Self = @This();

        pub const Rows: u8 = rows_count;
        pub const Cols: u8 = cols_count;
        pub const Region: p.Region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = Cols };

        const BitMap = algs_and_types.BitMap(Rows, Cols);

        alloc: std.mem.Allocator,
        floor: BitMap,
        walls: BitMap,
        // true for closed doors
        doors: std.AutoHashMap(p.Point, bool),

        // meta data about the dungeon:
        rooms: std.ArrayList(Room),
        passages: std.ArrayList(Passage),

        pub fn initEmpty(alloc: std.mem.Allocator) !Self {
            return .{
                .alloc = alloc,
                .floor = BitMap.initEmpty(),
                .walls = BitMap.initEmpty(),
                .rooms = std.ArrayList(Room).init(alloc),
                .passages = std.ArrayList(Passage).init(alloc),
                .doors = std.AutoHashMap(p.Point, bool).init(alloc),
            };
        }

        pub fn deinit(self: *Self) void {
            for (self.passages.items) |passage| {
                passage.deinit();
            }
            self.doors.deinit();
            self.rooms.deinit();
            self.passages.deinit();
        }

        /// For tests only
        fn parse(alloc: std.mem.Allocator, str: []const u8) !Self {
            if (!builtin.is_test) {
                @compileError("The function `parse` is for test purpose only");
            }
            return .{
                .alloc = alloc,
                .floor = try BitMap.parse('.', str),
                .walls = try BitMap.parse('#', str),
                .rooms = std.ArrayList(Room).init(alloc),
                .passages = std.ArrayList(Passage).init(alloc),
                .doors = std.AutoHashMap(p.Point, bool).init(alloc),
            };
        }

        pub inline fn cellAt(self: Self, place: p.Point) ?Cell {
            return self.cell(place.row, place.col);
        }

        pub fn cell(self: Self, row: u8, col: u8) ?Cell {
            if (row < 1 or row > Rows) {
                return null;
            }
            if (col < 1 or col > Cols) {
                return null;
            }
            if (self.doors.getPtr(.{ .row = row, .col = col })) |door| {
                return if (door.*) .closed_door else .opened_door;
            }
            if (self.walls.isSet(row, col)) {
                return .wall;
            }
            if (self.floor.isSet(row, col)) {
                return .floor;
            }
            return .nothing;
        }

        pub fn cellsInRegion(self: *const Self, region: p.Region) ?CellsIterator {
            if (Self.Region.intersect(region)) |reg| {
                return .{
                    .dungeon = self,
                    .region = reg,
                    .cursor = reg.top_left,
                };
            } else {
                return null;
            }
        }

        pub const CellsIterator = struct {
            dungeon: *const Self,
            region: p.Region,
            cursor: p.Point,

            pub fn next(self: *CellsIterator) ?Cell {
                if (!self.region.containsPoint(self.cursor))
                    return null;

                if (self.dungeon.cellAt(self.cursor)) |cl| {
                    self.cursor.move(.right);
                    if (self.cursor.col > self.region.bottomRight().col) {
                        self.cursor.col = self.region.top_left.col;
                        self.cursor.row += 1;
                    }
                    return cl;
                }
                return null;
            }
        };

        /// Basic BSP Dungeon generation
        /// https://www.roguebasin.com/index.php?title=Basic_BSP_Dungeon_generation
        pub fn bspGenerate(
            alloc: std.mem.Allocator,
            rand: std.Random,
        ) !Self {
            // this arena is used to build a BSP tree, which can be destroyed
            // right after completing the dungeon.
            var bsp_arena = std.heap.ArenaAllocator.init(alloc);
            defer _ = bsp_arena.deinit();

            var dungeon: Self = try initEmpty(alloc);

            // BSP helps to mark regions for rooms without intersections
            const root = try bsp.buildTree(&bsp_arena, rand, Rows, Cols, 10, 15);

            // visit every BSP node and generate rooms in the leafs
            var createRooms: TraverseAndCreateRooms = .{ .dungeon = &dungeon, .rand = rand };
            try root.traverse(createRooms.handler());

            // fold the BSP tree and binds nodes with the same parent:
            // var bindRooms: FoldAndBind = .{
            //     .dungeon = &dungeon,
            //     .rand = rand,
            // };
            // _ = try root.fold(bindRooms.handler());

            return dungeon;
        }

        const TraverseAndCreateRooms = struct {
            dungeon: *Self,
            rand: std.Random,

            fn handler(self: *TraverseAndCreateRooms) bsp.Tree.TraverseHandler {
                return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
            }

            fn createRoom(ptr: *anyopaque, node: *bsp.Tree) anyerror!void {
                if (!node.isLeaf()) return;
                const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
                try self.dungeon.generateAndAddRoom(self.rand, node.value);
            }
        };

        const FoldAndBind = struct {
            dungeon: *Self,
            rand: std.Random,

            fn handler(self: *FoldAndBind) bsp.Tree.FoldHandler {
                return .{ .ptr = self, .combine = FoldAndBind.bindRegions };
            }

            fn bindRegions(ptr: *anyopaque, p1: p.Region, p2: p.Region, depth: u8) anyerror!p.Region {
                const self: *FoldAndBind = @ptrCast(@alignCast(ptr));
                return try self.dungeon.createPassageBetweenRegions(self.rand, p1, p2, (depth % 2 == 0));
            }
        };

        fn generateAndAddRoom(self: *Self, rand: std.Random, region: p.Region) !void {
            const room = try self.generateSimpleRoom(rand, region);
            try self.rooms.append(room);
        }

        /// Creates floor and walls inside the region with random padding.
        /// Also, the count of rows and columns can be randomly reduced too.
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
        fn generateSimpleRoom(self: *Self, _: std.Random, region: p.Region) !Room {
            std.debug.assert(region.rows > 6);
            std.debug.assert(region.cols > 6);

            // copy the initial region
            const room = region;
            // generate inner region for the room:
            // const r_pad = rand.uintAtMost(u8, 4);
            // const c_pad = rand.uintAtMost(u8, 4);
            // room.top_left.row += r_pad;
            // room.top_left.col += c_pad;
            // room.rows -= (r_pad + rand.uintAtMost(u8, 4));
            // room.cols -= (c_pad + rand.uintAtMost(u8, 4));
            return self.createSimpleRoom(room);
        }

        fn createSimpleRoom(self: *Self, room: p.Region) Room {
            // generate walls:
            for (room.top_left.row..(room.top_left.row + room.rows)) |r| {
                if (r == room.top_left.row or r == room.bottomRight().row) {
                    self.walls.setRowValue(@intCast(r), room.top_left.col, room.cols, true);
                } else {
                    self.walls.set(@intCast(r), @intCast(room.top_left.col));
                    self.walls.set(@intCast(r), @intCast(room.bottomRight().col));
                }
            }
            // generate floor:
            var floor = room;
            floor.top_left.row += 1;
            floor.top_left.col += 1;
            floor.rows -= 2;
            floor.cols -= 2;
            self.floor.setRegionValue(floor, true);

            return room;
        }

        fn createPassageBetweenRegions(
            self: *Self,
            rand: std.Random,
            x: p.Region,
            y: p.Region,
            is_horizontal: bool,
        ) !p.Region {
            var passage: Passage = undefined;
            if (is_horizontal) {
                const left_region_door = self.findPlaceForDoorInRegionRnd(rand, x, .right) orelse return Error.NoSpaceForDoor;
                const right_region_door = self.findPlaceForDoorInRegionRnd(rand, y, .left) orelse return Error.NoSpaceForDoor;
                passage = try self.createPassage(rand, left_region_door, right_region_door);
            } else {
                const top_region_door = self.findPlaceForDoorInRegionRnd(rand, x, .bottom) orelse return Error.NoSpaceForDoor;
                const bottom_region_door = self.findPlaceForDoorInRegionRnd(rand, y, .top) orelse return Error.NoSpaceForDoor;
                passage = try self.createPassage(rand, top_region_door, bottom_region_door);
            }
            try self.passages.append(passage);
            try self.doors.put(passage.items[0], rand.boolean());
            try self.doors.put(passage.items[passage.items.len - 1], rand.boolean());
            return x.unionWith(y);
        }

        fn createPassage(self: *Self, _: std.Random, p1: p.Point, p2: p.Point) !Passage {
            var result = Passage.init(self.alloc);
            try result.append(p1);
            try result.append(p2);
            return result;
        }

        fn findPlaceForDoorInRegionRnd(self: Self, rand: std.Random, region: p.Region, side: p.Side) ?p.Point {
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
                "The point to start search of a place for door from the _{s}_ side is {any}. The region for search is {any}\n",
                .{ @tagName(side), place, region },
            );
            if (self.findFloorInDirection(side.opposite(), place, region)) |floor| {
                // try to move back to the wall:
                const candidate = floor.movedTo(side);
                if (self.cellAt(candidate) == .wall)
                    return candidate;
            }
            // try to find in the different parts of the region:
            var new_region: ?p.Region = null;
            if (side.isHorizontal()) {
                new_region = if (rand.boolean())
                    region.cropHorizontallyTo(place.row) orelse region.cropHorizontallyAfter(place.row)
                else
                    region.cropHorizontallyAfter(place.row) orelse region.cropHorizontallyTo(place.row);
            } else {
                new_region = if (rand.boolean())
                    region.cropVerticallyTo(place.col) orelse region.cropVerticallyAfter(place.col)
                else
                    region.cropVerticallyAfter(place.col) orelse region.cropVerticallyTo(place.col);
            }
            if (new_region) |reg| {
                return self.findPlaceForDoorInRegionRnd(rand, reg, side);
            } else {
                return null;
            }
        }

        /// Looks for an empty place with florr.
        /// Starting from the `start`, moves to the `direction`.
        /// Returns the found place or null.
        fn findFloorInDirection(self: Self, direction: p.Side, start: p.Point, region: p.Region) ?p.Point {
            var place = start;
            while (region.containsPoint(place) and self.cellAt(place) != .floor) {
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
    };
}

test "generate a simple room" {
    // given:
    const rows = 12;
    const cols = 12;
    var dungeon = try Dungeon(rows, cols).initEmpty(std.testing.allocator);
    defer dungeon.deinit();

    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };

    // when:
    const room = try dungeon.generateSimpleRoom(std.crypto.random, region);

    // then:
    try std.testing.expect(region.containsRegion(room));
    for (0..rows) |r_idx| {
        const r: u8 = @intCast(r_idx + 1);
        for (0..cols) |c_idx| {
            const c: u8 = @intCast(c_idx + 1);
            errdefer std.debug.print("r:{d} c:{d}\n", .{ r, c });

            const cell = dungeon.cell(r, c);
            if (room.contains(r, c)) {
                const expect_wall =
                    (r == room.top_left.row or r == room.bottomRight().row or
                    c == room.top_left.col or c == room.bottomRight().col);
                if (expect_wall) {
                    try std.testing.expectEqual(.wall, cell);
                } else {
                    try std.testing.expectEqual(.floor, cell);
                }
            } else {
                try std.testing.expectEqual(.nothing, cell);
            }
        }
    }
}

test "find a cell with floor inside the room starting outside" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon(4, 5).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = Dungeon(4, 5).Region;

    // when:
    const expected = dungeon.findFloorInDirection(
        .right,
        p.Point{ .row = 2, .col = 1 },
        region,
    );
    const unexpected = dungeon.findFloorInDirection(
        .right,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 3 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find a cell with floor inside the room starting on the wall" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon(4, 5).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = Dungeon(4, 5).Region;

    // when:
    const expected = dungeon.findFloorInDirection(
        .bottom,
        p.Point{ .row = 1, .col = 3 },
        region,
    );
    const unexpected = dungeon.findFloorInDirection(
        .bottom,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 3 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find a random place for door" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon(4, 5).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = Dungeon(4, 5).Region;
    const rand = std.crypto.random;

    // when:
    const place_left = dungeon.findPlaceForDoorInRegionRnd(rand, region, .left);
    const place_bottom = dungeon.findPlaceForDoorInRegionRnd(rand, region, .bottom);

    // then:
    errdefer std.debug.print("place left {any}\n", .{place_left});
    try std.testing.expectEqual(2, place_left.?.col);
    try std.testing.expect(2 <= place_left.?.row and place_left.?.row <= 3);
    // and
    errdefer std.debug.print("place bottom {any}\n", .{place_bottom});
    try std.testing.expectEqual(4, place_bottom.?.row);
    try std.testing.expect(3 <= place_bottom.?.col and place_bottom.?.col <= 4);
}

test {
    std.testing.refAllDecls(@This());
}
