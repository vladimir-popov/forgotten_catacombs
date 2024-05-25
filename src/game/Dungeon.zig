const std = @import("std");
const builtin = @import("builtin");
const algs_and_types = @import("algs_and_types");

const bsp = algs_and_types.BSP;
const p = algs_and_types.primitives;

const log = std.log.scoped(.dungeon);

pub const Error = error{
    NoSpaceForDoor,
    PassageCantBeCreated,
};

pub const Room = p.Region;

pub const Passage = struct {
    const Turn = struct {
        place: p.Point,
        to_direction: p.Direction,
    };

    turns: std.ArrayList(Turn),

    fn init(
        rand: std.Random,
        dungeon_ptr: anytype,
        from: p.Point,
        to: p.Point,
        direction: p.Direction,
    ) !Passage {
        log.debug("Create passage from {any} {s} to {any}", .{ from, @tagName(direction), to });
        var passage: Passage = .{ .turns = std.ArrayList(Turn).init(dungeon_ptr.*.alloc) };
        errdefer passage.deinit();
        try passage.turns.append(.{ .place = from, .to_direction = direction });
        if (direction.isHorizontal() and from.row != to.row) {
            try passage.addTurn("col", "row", rand, from, to, direction);
        }
        if (direction.isVertical() and from.col != to.col) {
            try passage.addTurn("row", "col", rand, from, to, direction);
        }
        try passage.turns.append(.{ .place = to, .to_direction = direction });
        return passage;
    }

    fn deinit(self: Passage) void {
        self.turns.deinit();
    }

    fn addTurn(
        self: *Passage,
        comptime in_direction_field: []const u8,
        comptime orthogonal_field: []const u8,
        rand: std.Random,
        from: p.Point,
        to: p.Point,
        direction: p.Direction,
    ) !void {
        var min: u8 = @field(from, in_direction_field);
        var max: u8 = @field(to, in_direction_field);
        var is_clockwise: bool = if (direction.isHorizontal())
            // example: moving to the right, but the destination is bottom
            @field(from, orthogonal_field) < @field(to, orthogonal_field)
        else
            // example: moving down, but the destination is on right
            @field(from, orthogonal_field) > @field(to, orthogonal_field);

        if (min > max) {
            is_clockwise = !is_clockwise;
            const tmp = min;
            min = max;
            max = tmp;
        }
        const middle = rand.intRangeAtMost(u8, min + 1, max - 1);

        var turn: Turn = undefined;
        turn.to_direction = direction.rotatedClockwise(is_clockwise);
        @field(turn.place, in_direction_field) = middle;
        @field(turn.place, orthogonal_field) = @field(from, orthogonal_field);
        log.debug("Turn on {any} to {s}", .{ turn.place, @tagName(turn.to_direction) });
        try self.turns.append(turn);

        turn.to_direction = direction;
        @field(turn.place, orthogonal_field) = @field(to, orthogonal_field);
        log.debug("Turn on {any} to {s}", .{ turn.place, @tagName(turn.to_direction) });
        try self.turns.append(turn);
    }

    test "create passage between two points" {
        // given:
        const Rows = 10;
        const Cols = 10;
        const seed = std.crypto.random.int(u64);
        errdefer std.debug.print("Seed: {d}\n", .{seed});
        var dungeon = try Dungeon(Rows, Cols).initEmpty(std.testing.allocator);
        defer dungeon.deinit();
        const from = p.Point{ .row = 1, .col = 1 };
        const to = p.Point{ .row = Rows, .col = Cols };
        var rand = std.rand.DefaultPrng.init(seed);

        // when:
        const result = try Passage.init(rand.random(), &dungeon, from, to, .down);
        defer result.deinit();

        // then:
        try std.testing.expectEqual(4, result.turns.items.len);
        try std.testing.expectEqualDeep(from, result.turns.items[0].place);
        try std.testing.expectEqualDeep(to, result.turns.getLast().place);
        try std.testing.expectEqual(.down, result.turns.items[0].to_direction);
        try std.testing.expectEqual(.right, result.turns.items[1].to_direction);
        try std.testing.expectEqual(.down, result.turns.items[2].to_direction);
    }
};

pub const Cell = enum { nothing, floor, wall, opened_door, closed_door };

pub fn Dungeon(comptime rows_count: u8, cols_count: u8) type {
    return struct {
        /// The dungeon. Contains walls, doors, rooms and passages of the level.
        const Self = @This();

        pub const Rows: u8 = rows_count;
        pub const Cols: u8 = cols_count;
        pub const Region: p.Region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = Cols };

        // rows / cols - for terminal it's less than 0.
        // TODO make it as argument
        const SquareRation: f16 = 0.4;

        const BitMap = algs_and_types.BitMap(Rows, Cols);

        alloc: std.mem.Allocator,
        floor: BitMap,
        walls: BitMap,
        // true for opened doors
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
            self.passages.deinit();
            self.doors.deinit();
            self.rooms.deinit();
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
                return if (door.*) .opened_door else .closed_door;
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

        fn cleanAt(self: *Self, place: p.Point) void {
            if (!Region.containsPoint(place)) {
                return;
            }
            self.floor.unsetAt(place);
            self.walls.unsetAt(place);
            _ = self.doors.remove(place);
        }

        fn createDoorAt(self: *Self, place: p.Point, is_open: bool) !void {
            if (!Region.containsPoint(place)) {
                return;
            }
            self.floor.unsetAt(place);
            self.walls.unsetAt(place);
            try self.doors.put(place, is_open);
        }

        fn createWallAt(self: *Self, place: p.Point) !void {
            if (!Region.containsPoint(place)) {
                return;
            }
            self.floor.unsetAt(place);
            _ = self.doors.remove(place);
            self.walls.setAt(place);
        }

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
            const root = try bsp.buildTree(&bsp_arena, rand, Rows, Cols, .{});

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

        fn generateAndAddRoom(self: *Self, rand: std.Random, region: p.Region) !void {
            const room = try self.generateSimpleRoom(rand, region, .{});
            try self.rooms.append(room);
        }

        /// Configuration of the simple rooms.
        const SimpleRoomOpts = struct {
            /// Minimal rows count in the room
            min_rows: u8 = 5,
            /// Minimal columns count in the room
            min_cols: u8 = 5,
            /// Minimal scale rate to prevent too small rooms
            min_scale: f16 = 0.6,
            /// This is rows/cols ratio of the square.
            /// In case of ascii graphics it's not 1.0
            square_ratio: f16 = SquareRation,

            /// Minimal area of the room
            inline fn minArea(self: SimpleRoomOpts) u8 {
                return self.min_rows * self.min_cols;
            }
        };

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
        fn generateSimpleRoom(self: *Self, rand: std.Random, region: p.Region, opts: SimpleRoomOpts) !Room {
            var room: p.Region = region;
            if (!std.math.approxEqAbs(f16, opts.square_ratio, region.ratio(), 0.1)) {
                // make the region 'more square'
                if (region.ratio() > opts.square_ratio) {
                    room.rows = @max(
                        opts.min_rows,
                        @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.cols)) * opts.square_ratio))),
                    );
                } else {
                    room.cols = @max(
                        opts.min_cols,
                        @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.rows)) / opts.square_ratio))),
                    );
                }
            }
            var scale: f16 = @floatFromInt(1 + rand.uintLessThan(u16, room.area() - opts.minArea()));
            scale = scale / @as(f16, @floatFromInt(room.area()));
            room.scale(@max(opts.min_scale, scale));
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

        const FoldAndBind = struct {
            dungeon: *Self,
            rand: std.Random,

            fn handler(self: *FoldAndBind) bsp.Tree.FoldHandler {
                return .{ .ptr = self, .combine = FoldAndBind.bindRegions };
            }

            fn bindRegions(ptr: *anyopaque, r1: p.Region, r2: p.Region, _: u8) anyerror!p.Region {
                const self: *FoldAndBind = @ptrCast(@alignCast(ptr));
                const direction: p.Direction = if (r1.top_left.row == r2.top_left.row) .right else .down;
                return try self.dungeon.createAndAddPassageBetweenRegions(self.rand, r1, r2, direction);
            }
        };

        fn createAndAddPassageBetweenRegions(
            self: *Self,
            rand: std.Random,
            r1: p.Region,
            r2: p.Region,
            direction: p.Direction,
        ) !p.Region {
            const door1 = self.findPlaceForDoorInRegionRnd(rand, r1, direction.asSide()) orelse
                return Error.NoSpaceForDoor;
            const door2 = self.findPlaceForDoorInRegionRnd(rand, r2, direction.asSide().opposite()) orelse
                return Error.NoSpaceForDoor;

            const passage = try Passage.init(rand, self, door1, door2, direction);
            var prev_turn = passage.turns.items[0];
            for (passage.turns.items[1..]) |turn| {
                try self.dig(prev_turn.place, turn.place, prev_turn.to_direction);
                prev_turn = turn;
            }
            try self.createDoorAt(door1, rand.boolean());
            try self.createDoorAt(door2, rand.boolean());
            return r1.unionWith(r2);
        }

        fn dig(self: *Self, from: p.Point, to: p.Point, direction: p.Direction) !void {
            var point = from;
            while (!std.meta.eql(point, to)) {
                if (self.cellAt(point) == .wall) {
                    try self.createDoorAt(point, true);
                } else {
                    try self.createWallAt(point.movedTo(direction.rotatedClockwise(false)));
                    self.floor.setAt(point);
                    try self.createWallAt(point.movedTo(direction.rotatedClockwise(true)));
                }
                point.move(direction);
            }
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
                "Start search of a place for door from {any} on the _{s}_ side of the {any}",
                .{ place, @tagName(side), region },
            );
            if (self.findFloorInDirection(side.asDirection().opposite(), place, region)) |floor| {
                // try to move back to the wall:
                const candidate = floor.movedTo(side.asDirection());
                if (self.cellAt(candidate) == .wall) {
                    log.debug("{any} is the place for door in {any} on {s} side", .{ candidate, region, @tagName(side) });
                    return candidate;
                }
            }
            // try to find in the different parts of the region:
            var new_regions: [2]?p.Region = .{ null, null };
            if (side.isHorizontal()) {
                new_regions = if (rand.boolean())
                    .{ region.cropVerticallyTo(place.col), region.cropVerticallyAfter(place.col) }
                else
                    .{ region.cropVerticallyAfter(place.col), region.cropVerticallyTo(place.col) };
                log.debug("Crop {any} vertically to {any} and {any}", .{ region, new_regions[0], new_regions[1] });
            } else {
                new_regions = if (rand.boolean())
                    .{ region.cropHorizontallyTo(place.row), region.cropHorizontallyAfter(place.row) }
                else
                    .{ region.cropHorizontallyAfter(place.row), region.cropHorizontallyTo(place.row) };
                log.debug("Crop {any} horizontally to {any} and {any}", .{ region, new_regions[0], new_regions[1] });
            }
            for (new_regions) |new_region| {
                if (new_region) |reg| {
                    reg.validate();
                    if (self.findPlaceForDoorInRegionRnd(rand, reg, side)) |result| {
                        log.debug("{any} is the place for door in {any} on {s} side", .{ result, reg, @tagName(side) });
                        return result;
                    }
                }
            }
            log.debug("Not found any place for door in {any} on {s} side", .{ region, @tagName(side) });
            return null;
        }

        /// Looks for an empty place with the floor.
        /// Starting from the `start`, moves to the `direction`.
        /// Returns the found place or null.
        fn findFloorInDirection(self: Self, direction: p.Direction, start: p.Point, region: p.Region) ?p.Point {
            var place = start;
            while (region.containsPoint(place) and self.cellAt(place) != .floor) {
                place.move(direction);
            }
            if (self.doors.contains(place.movedTo(direction.rotatedClockwise(true))) or
                self.doors.contains(place.movedTo(direction.rotatedClockwise(false))))
            {
                return null;
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
    const Rows = 12;
    const Cols = 12;
    var dungeon = try Dungeon(Rows, Cols).initEmpty(std.testing.allocator);
    defer dungeon.deinit();

    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };

    // when:
    const room = try dungeon.generateSimpleRoom(std.crypto.random, region, .{});

    // then:
    try std.testing.expect(region.containsRegion(room));
    for (0..Rows) |r_idx| {
        const r: u8 = @intCast(r_idx + 1);
        for (0..Cols) |c_idx| {
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
        .down,
        p.Point{ .row = 1, .col = 3 },
        region,
    );
    const unexpected = dungeon.findFloorInDirection(
        .down,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 3 }, expected.?);
    try std.testing.expect(unexpected == null);
}
test "find a random place for the door on the left side" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon(4, 5).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = Dungeon(4, 5).Region;
    const rand = std.crypto.random;

    // when:
    const place_left = dungeon.findPlaceForDoorInRegionRnd(rand, region, .left);

    // then:
    errdefer std.debug.print("place left {any}\n", .{place_left});
    try std.testing.expectEqual(2, place_left.?.col);
    try std.testing.expect(2 <= place_left.?.row and place_left.?.row <= 3);
}

test "find a random place for the door on the bottom side" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon(4, 5).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = Dungeon(4, 5).Region;
    const rand = std.crypto.random;

    // when:
    const place_bottom = dungeon.findPlaceForDoorInRegionRnd(rand, region, .bottom);

    // then:
    errdefer std.debug.print("place bottom {any}\n", .{place_bottom});
    try std.testing.expectEqual(4, place_bottom.?.row);
    try std.testing.expect(3 <= place_bottom.?.col and place_bottom.?.col <= 4);
}

test "create passage between two rooms" {
    // given:
    const Rows = 4;
    const Cols = 12;
    const str =
        \\ ####   ####
        \\ #..#   #..#
        \\ #..#   #..#
        \\ ####   ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon(Rows, Cols).parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const rand = std.crypto.random;
    const r1 = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = 6 };
    const r2 = p.Region{ .top_left = .{ .row = 1, .col = 7 }, .rows = Rows, .cols = Cols - 6 };

    // when:
    const region = try dungeon.createAndAddPassageBetweenRegions(rand, r1, r2, .right);

    // then:
    try std.testing.expectEqualDeep(Dungeon(Rows, Cols).Region, region);
    const passage: Passage = dungeon.passages.items[0];
    errdefer std.debug.print("Passage: {any}\n", .{passage.turns.items});
    try std.testing.expect(passage.turns.items.len >= 2);
}

test {
    std.testing.refAllDecls(@This());
}
