const std = @import("std");
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

        pub fn cellsInRegion(self: *const Self, region: p.Region) ?CellsIterator {
            if (Self.Region.intersect(region)) |reg| {
                const start_place: p.Point = .{ .row = reg.top_left.row, .col = reg.top_left.col };
                return .{
                    .dungeon = self,
                    .start_place = start_place,
                    .bottom_right_limit = reg.bottomRight(),
                    // -1 for col, coz we will begin iteration from the moving the current place
                    .current_place = start_place.movedTo(.left),
                };
            } else {
                return null;
            }
        }

        pub const CellsIterator = struct {
            dungeon: *const Self,
            start_place: p.Point,
            bottom_right_limit: p.Point,
            current_place: p.Point,

            pub fn next(self: *CellsIterator) ?Cell {
                self.current_place.move(.right);
                if (self.current_place.col > self.bottom_right_limit.col) {
                    self.current_place.col = self.start_place.col;
                    self.current_place.row += 1;
                }
                if (self.current_place.row > self.bottom_right_limit.row) {
                    return null;
                }
                if (self.dungeon.doors.getPtr(self.current_place)) |door| {
                    return if (door.*) .closed_door else .opened_door;
                }
                if (self.dungeon.walls.isSet(self.current_place.row, self.current_place.col)) {
                    return .wall;
                }
                if (self.dungeon.floor.isSet(self.current_place.row, self.current_place.col)) {
                    return .floor;
                }
                return .nothing;
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
            const root = try bsp.buildTree(&bsp_arena, rand, Rows, Cols, 8, 15);

            // visit every BSP node and generate rooms in the leafs
            var createRooms: TraverseAndCreateRooms = .{ .dungeon = &dungeon, .rand = rand };
            try root.traverse(createRooms.handler());

            // fold the BSP tree and binds nodes with the same parent:
            var bindRooms: FoldAndBind = .{
                .dungeon = &dungeon,
                .rand = rand,
            };
            _ = try root.fold(bindRooms.handler());

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

            fn bindRegions(ptr: *anyopaque, x: p.Region, y: p.Region, depth: u8) anyerror!p.Region {
                const self: *FoldAndBind = @ptrCast(@alignCast(ptr));
                return try self.dungeon.createPassageBetweenRegions(self.rand, x, y, (depth % 2 == 0));
            }
        };

        fn generateAndAddRoom(self: *Self, rand: std.Random, region: p.Region) !void {
            const room = try self.generateSimpleRoom(rand, region);
            try self.rooms.append(room);
        }

        /// Creates walls inside the region with random padding in the range [0:2].
        /// Also, the count of rows and columns can be randomly reduced too in the same range.
        /// The minimal size of the region is 7x7.
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
        fn generateSimpleRoom(self: *Self, rand: std.Random, region: p.Region) !Room {
            std.debug.assert(region.rows > 6);
            std.debug.assert(region.cols > 6);

            // copy the initial region
            var room = region;
            // generate inner region for the room:
            const r_pad = rand.uintAtMost(u8, 2);
            const c_pad = rand.uintAtMost(u8, 2);
            room.top_left.row += r_pad;
            room.top_left.col += c_pad;
            room.rows -= (r_pad + rand.uintAtMost(u8, 2));
            room.cols -= (c_pad + rand.uintAtMost(u8, 2));
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

        fn createPassage(self: *Self, _: std.Random, _: p.Point, _: p.Point) !Passage {
            return Passage.init(self.alloc);
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

        /// Looks for an empty place **inside** a room or a passage in the `region`.
        /// Starting from the `start`, moves to the `direction`.
        /// Returns the found place or null.
        fn findEmptyPlaceInDirection(self: Self, direction: p.Side, start: p.Point, region: p.Region) ?p.Point {
            var place = start;
            var cross_the_wall: bool = false;
            blk: while (region.containsPoint(place)) {
                const is_wall = self.walls.isSet(place.row, place.col);
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
    };
}
//
// test "generate a simple room" {
//     // given:
//     const rows = 12;
//     const cols = 12;
//     var walls = try Walls.initEmpty(std.testing.allocator, rows, cols);
//     defer walls.deinit();
//     const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };
//
//     var generator = SimpleRoomGenerator{ .rand = std.crypto.random };
//
//     // when:
//     const room = try generator.generator().createRoom(&walls, region);
//
//     // then:
//     try std.testing.expect(region.containsRegion(room));
//     for (0..rows) |r_idx| {
//         const r: u8 = @intCast(r_idx + 1);
//         for (0..cols) |c_idx| {
//             const c: u8 = @intCast(c_idx + 1);
//             const cell = walls.isWall(r, c);
//             const expect = room.contains(r, c) and
//                 (r == room.top_left.row or r == room.bottomRight().row or
//                 c == room.top_left.col or c == room.bottomRight().col);
//             try std.testing.expectEqual(expect, cell);
//         }
//     }
// }
//
// test "find an empty place inside the room in the region from right to left" {
//     // given:
//     const str =
//         \\####.
//         \\#..#.
//         \\#..#.
//         \\####.
//     ;
//     var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
//     defer dungeon.deinit();
//     try dungeon.walls.parse(str);
//
//     // when:
//     const expected = dungeon.findEmptyPlaceInDirection(
//         .left,
//         p.Point{ .row = 2, .col = 5 },
//         dungeon.getRegion(),
//     );
//     const unexpected = dungeon.findEmptyPlaceInDirection(
//         .left,
//         p.Point{ .row = 1, .col = 5 },
//         dungeon.getRegion(),
//     );
//
//     // then:
//     try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 3 }, expected.?);
//     try std.testing.expect(unexpected == null);
// }
//
// test "find an empty place inside the room in the region from bottom to top" {
//     // given:
//     const str =
//         \\####.
//         \\#..#.
//         \\#..#.
//         \\####.
//     ;
//     var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
//     defer dungeon.deinit();
//     try dungeon.walls.parse(str);
//
//     // when:
//     const expected = dungeon.findEmptyPlaceInDirection(
//         .bottom,
//         p.Point{ .row = 4, .col = 2 },
//         dungeon.getRegion(),
//     );
//     const unexpected = dungeon.findEmptyPlaceInDirection(
//         .bottom,
//         p.Point{ .row = 4, .col = 1 },
//         dungeon.getRegion(),
//     );
//
//     // then:
//     try std.testing.expectEqualDeep(p.Point{ .row = 3, .col = 2 }, expected.?);
//     try std.testing.expect(unexpected == null);
// }
//
// test "find a random place for door" {
//     // given:
//     const str =
//         \\####.
//         \\#..#.
//         \\#..#.
//         \\####.
//     ;
//     const rand = std.crypto.random;
//     var dungeon = try Dungeon.initEmpty(std.testing.allocator, 4, 5);
//     defer dungeon.deinit();
//     try dungeon.walls.parse(str);
//     const region: p.Region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };
//
//     // when:
//     const place_right = dungeon.findPlaceForDoorInRegionRnd(rand, region, .right).?;
//     // const place_bottom = try dungeon.findPlaceForDoorRnd(rand, region, .bottom);
//
//     // then:
//     try std.testing.expectEqual(4, place_right.col);
//     try std.testing.expect(2 <= place_right.row and place_right.row <= 3);
//     // and
//     // try std.testing.expectEqual(4, place_bottom.row);
//     // try std.testing.expect(2 <= place_bottom.col and place_bottom.col <= 3);
// }

test {
    std.testing.refAllDecls(@This());
}
