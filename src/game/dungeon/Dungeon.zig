/// This is value object which represents the dungeon as bitmaps with the
/// walls and floor, list of the doors, list of the regions for rooms, and list
/// of the passages.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

pub const Error = error{
    NoSpaceForDoor,
    PassageCantBeCreated,
};

pub const Map = @import("Map.zig");
pub const Passage = @import("Passage.zig");
pub const Room = p.Region;
const Rooms = @import("Rooms.zig");

/// Possible types of objects inside the dungeon.
pub const Cell = enum {
    nothing,
    floor,
    wall,
    door,
};

const log = std.log.scoped(.dungeon);

pub const ROWS = g.DISPLAY_ROWS * 3;
pub const COLS = g.DISPLAY_COLS * 3;
pub const REGION: p.Region = .{
    .top_left = .{ .row = 1, .col = 1 },
    .rows = ROWS,
    .cols = COLS,
};

const Dungeon = @This();

/// The list of the dungeon's rooms. Usually, the first room in the list has entrance to the dungeon,
/// and the last has exit.
rooms: std.ArrayList(Room),
/// Passages connect rooms and other passages.
/// The first tunnel begins from the door, and the last one doesn't have the end.
passages: std.ArrayList(Passage),
/// The set of places where doors are inside the dungeon.
doors: std.AutoHashMap(p.Point, void),
/// The bit mask of the places with floor.
floor: p.BitMap(ROWS, COLS),
/// The bit mask of the places with walls. The floor under the walls is undefined, it can be set, or can be omitted.
walls: p.BitMap(ROWS, COLS),

/// Creates an empty dungeon.
pub fn init(alloc: std.mem.Allocator) !Dungeon {
    return .{
        .floor = try p.BitMap(ROWS, COLS).initEmpty(alloc),
        .walls = try p.BitMap(ROWS, COLS).initEmpty(alloc),
        .doors = std.AutoHashMap(p.Point, void).init(alloc),
        .rooms = std.ArrayList(Room).init(alloc),
        .passages = std.ArrayList(Passage).init(alloc),
    };
}

pub fn deinit(self: *Dungeon) void {
    self.floor.deinit();
    self.walls.deinit();
    self.doors.deinit();
    for (self.passages.items) |passage| {
        passage.deinit();
    }
    self.passages.deinit();
    self.rooms.deinit();
}

pub fn clearRetainingCapacity(self: *Dungeon) void {
    self.floor.clear();
    self.walls.clear();
    self.doors.clearRetainingCapacity();
    for (self.passages.items) |passage| {
        passage.deinit();
    }
    self.passages.clearRetainingCapacity();
    self.rooms.clearRetainingCapacity();
}

pub inline fn cellAt(self: Dungeon, place: p.Point) ?Cell {
    if (place.row < 1 or place.row > ROWS) {
        return null;
    }
    if (place.col < 1 or place.col > COLS) {
        return null;
    }
    if (self.doors.get(place)) |_| {
        return .door;
    }
    if (self.walls.isSet(place.row, place.col)) {
        return .wall;
    }
    if (self.floor.isSet(place.row, place.col)) {
        return .floor;
    }
    return .nothing;
}

pub inline fn isCellAt(self: Dungeon, place: p.Point, assumption: Cell) bool {
    if (self.cellAt(place)) |cl| return cl == assumption else return false;
}

pub const CellsIterator = struct {
    dungeon: *const Dungeon,
    region: p.Region,
    next_place: p.Point,
    current_place: p.Point = undefined,

    pub fn next(self: *CellsIterator) ?Cell {
        self.current_place = self.next_place;
        if (!self.region.containsPoint(self.current_place))
            return null;

        if (self.dungeon.cellAt(self.current_place)) |cl| {
            self.next_place = self.current_place.movedTo(.right);
            if (self.next_place.col > self.region.bottomRightCol()) {
                self.next_place.col = self.region.top_left.col;
                self.next_place.row += 1;
            }
            return cl;
        }
        return null;
    }
};

pub fn cellsInRegion(self: *const Dungeon, region: p.Region) ?CellsIterator {
    if (REGION.intersect(region)) |reg| {
        return .{
            .dungeon = self,
            .region = reg,
            .next_place = reg.top_left,
        };
    } else {
        return null;
    }
}

pub fn cellsAround(self: Dungeon, place: p.Point) ?CellsIterator {
    return self.cellsInRegion(.{
        .top_left = .{
            .row = @max(place.row - 1, 1),
            .col = @max(place.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    });
}

/// For tests only
pub fn parse(alloc: std.mem.Allocator, str: []const u8) !Dungeon {
    if (!@import("builtin").is_test) {
        @compileError("The function `parse` is for test purpose only");
    }
    var dungeon = try Dungeon.init(alloc);
    try dungeon.floor.parse('.', str);
    try dungeon.walls.parse('#', str);
    return dungeon;
}

// ==================================================
//       Methods for modification.
//       Usually used by the dungeon generators.
// ==================================================

pub fn generateAndAddRoom(self: *Dungeon, rand: std.Random, region: p.Region) !void {
    const room = try Rooms.createRoom(self, rand, region);
    try self.rooms.append(room);
}

pub fn createAndAddPassageBetweenRegions(
    self: *Dungeon,
    // alloc is used here to run recursions on the heap
    alloc: std.mem.Allocator,
    rand: std.Random,
    r1: p.Region,
    r2: p.Region,
) !p.Region {
    var stack_arena = std.heap.ArenaAllocator.init(alloc);
    defer _ = stack_arena.deinit();

    const direction: p.Direction = if (r1.top_left.row == r2.top_left.row) .right else .down;
    const door1 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r1, direction) orelse
        return Error.NoSpaceForDoor;
    const door2 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r2, direction.opposite()) orelse
        return Error.NoSpaceForDoor;

    const passage = try self.passages.addOne();
    errdefer _ = self.passages.orderedRemove(self.passages.items.len - 1);

    passage.turns = std.ArrayList(Passage.Turn).init(alloc);
    errdefer passage.deinit();

    log.debug("Found places for doors: {any}; {any}. Prepare the passage between them...", .{ door1, door2 });
    _ = try passage.turnAt(door1, direction);
    if (door1.row != door2.row and door1.col != door2.col) {
        // intersection of the passage from the door 1 and region 1
        var middle1: p.Point = if (direction.isHorizontal())
            // left or right
            .{ .row = door1.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = door1.col };

        // intersection of the passage from the region 1 and door 2
        var middle2: p.Point = if (direction.isHorizontal())
            // left or right
            .{ .row = door2.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = door2.col };

        // try to find better places for turn:
        if (try self.findPlaceForPassageTurn(&stack_arena, door1, door2, direction.isHorizontal(), 0)) |places| {
            middle1 = places[0];
            middle2 = places[1];
        }

        var turn = try passage.turnToPoint(middle1, middle2);

        turn = try passage.turnToPoint(middle2, door2);
    }
    _ = try passage.turnAt(door2, direction);
    log.debug("The passage was prepared: {any}", .{passage});

    try self.digPassage(passage);
    try self.forceCreateDoorAt(door1);
    try self.forceCreateDoorAt(door2);

    return r1.unionWith(r2);
}

/// Removes doors, floor and walls on the passed place.
pub fn cleanAt(self: *Dungeon, place: p.Point) void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    self.floor.unsetAt(place);
    self.walls.unsetAt(place);
    _ = self.doors.remove(place);
}

/// Removes doors, floor and walls on the passed place, and create a new door.
pub fn forceCreateFloorAt(self: *Dungeon, place: p.Point) !void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.floor.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new wall.
pub fn forceCreateWallAt(self: Dungeon, place: p.Point) !void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.walls.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a cell with floor.
pub fn forceCreateDoorAt(self: *Dungeon, place: p.Point) !void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    try self.doors.put(place, {});
}

/// Creates the cell with wall only if nothing exists on the passed place.
fn createWallAt(self: *Dungeon, place: p.Point) void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    if (self.isCellAt(place, .nothing)) {
        self.walls.setAt(place);
    }
}

/// Creates the cell with floor only if nothing exists on the passed place.
pub fn createFloorAt(self: *Dungeon, place: p.Point) void {
    if (!Dungeon.REGION.containsPoint(place)) {
        return;
    }
    if (self.isCellAt(place, .nothing)) {
        self.floor.setAt(place);
    }
}

/// Trying to find a line between `from` and `to` with `nothing` cells only.
/// Gives up after MAX_ATTEMPTS attempts to prevent long search.
fn findPlaceForPassageTurn(
    self: Dungeon,
    stack_arena: *std.heap.ArenaAllocator,
    init_from: p.Point,
    init_to: p.Point,
    is_horizontal: bool,
    attempt: u8,
) !?struct { p.Point, p.Point } {
    const MAX_ATTEMPTS = 5;
    // to prevent infinite loop
    var current_attempt = attempt;
    var stack = std.ArrayList(struct { p.Point, p.Point }).init(stack_arena.allocator());
    try stack.append(.{ init_from, init_to });
    var middle1: p.Point = undefined;
    var middle2: p.Point = undefined;
    while (stack.popOrNull()) |points| {
        const from = points[0];
        const to = points[1];
        const distance: u8 = if (is_horizontal)
            to.col - from.col
        else
            to.row - from.row;

        if (distance > 4 and current_attempt < MAX_ATTEMPTS) {
            if (is_horizontal) {
                middle1.row = from.row;
                middle1.col = distance / 2 + from.col;
                middle2.row = to.row;
                middle2.col = middle1.col;
            } else {
                middle1.row = distance / 2 + from.row;
                middle1.col = from.col;
                middle2.row = middle1.row;
                middle2.col = to.col;
            }
            if (self.isFreeLine(middle1, middle2)) {
                return .{ middle1, middle2 };
            }
            current_attempt += 1;
            try stack.append(.{ from, middle2 });
            try stack.append(.{ middle1, to });
        }
    }
    return null;
}

fn isFreeLine(self: Dungeon, from: p.Point, to: p.Point) bool {
    const direction: p.Direction = if (from.col == to.col and from.row < to.row)
        .down
    else if (from.col == to.col and from.row > to.row)
        .up
    else if (from.row == to.row and from.col < to.col)
        .right
    else if (from.row == to.row and from.col > to.col)
        .left
    else
        unreachable;
    var cursor = from;
    while (!std.meta.eql(cursor, to)) {
        if (self.isCellAt(cursor, .nothing))
            cursor.move(direction)
        else
            return false;
    }
    return true;
}

fn digPassage(self: *Dungeon, passage: *const Passage) !void {
    var prev: Passage.Turn = passage.turns.items[0];
    for (passage.turns.items[1 .. passage.turns.items.len - 1]) |turn| {
        try self.dig(prev.place, turn.place, prev.to_direction);
        try self.digTurn(turn.place, prev.to_direction, turn.to_direction);
        prev = turn;
    }
    try self.dig(prev.place, passage.turns.getLast().place, prev.to_direction);
}

fn dig(self: *Dungeon, from: p.Point, to: p.Point, direction: p.Direction) !void {
    var point = from;
    while (true) {
        self.createWallAt(point.movedTo(direction.rotatedClockwise(false)));
        self.createWallAt(point.movedTo(direction.rotatedClockwise(true)));
        self.createFloorAt(point);
        if (std.meta.eql(point, to))
            break;
        point.move(direction);
    }
}

fn digTurn(self: *Dungeon, at: p.Point, from: p.Direction, to: p.Direction) !void {
    // wrap the corner by walls
    const reg: p.Region = .{ .top_left = at.movedTo(.up).movedTo(.left), .rows = 3, .cols = 3 };
    var itr = reg.cells();
    while (itr.next()) |cl| {
        self.createWallAt(cl);
    }
    // create the floor in the turn
    try self.forceCreateFloorAt(at);
    try self.forceCreateFloorAt(at.movedTo(from.opposite()));
    try self.forceCreateFloorAt(at.movedTo(to));
}

fn findPlaceForDoorInRegionRnd(
    self: Dungeon,
    stack_arena: *std.heap.ArenaAllocator,
    rand: std.Random,
    init_region: p.Region,
    side: p.Direction,
) !?p.Point {
    var stack = std.ArrayList(p.Region).init(stack_arena.allocator());
    try stack.append(init_region);
    while (stack.popOrNull()) |region| {
        const place = switch (side) {
            .up => p.Point{
                .row = region.top_left.row,
                .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRightCol()),
            },
            .down => p.Point{
                .row = region.bottomRightRow(),
                .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRightCol()),
            },
            .left => p.Point{
                .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRightRow()),
                .col = region.top_left.col,
            },
            .right => p.Point{
                .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRightRow()),
                .col = region.bottomRightCol(),
            },
        };
        if (self.findPlaceForDoor(side.opposite(), place, region)) |candidate| {
            if (self.cellAt(candidate)) |cl| {
                switch (cl) {
                    .wall => {
                        return candidate;
                    },
                    else => {},
                }
            }
        }
        // try to find in the different parts of the region:
        var new_regions: [2]?p.Region = .{ null, null };
        if (side == .up or side == .down) {
            new_regions = if (rand.boolean())
                .{ region.croppedVerticallyTo(place.col), region.croppedVerticallyAfter(place.col) }
            else
                .{ region.croppedVerticallyAfter(place.col), region.croppedVerticallyTo(place.col) };
        } else {
            new_regions = if (rand.boolean())
                .{ region.croppedHorizontallyTo(place.row), region.croppedHorizontallyAfter(place.row) }
            else
                .{ region.croppedHorizontallyAfter(place.row), region.croppedHorizontallyTo(place.row) };
        }
        for (new_regions) |new_region| {
            if (new_region) |reg| {
                reg.validate();
                try stack.append(reg);
            }
        }
    }
    return null;
}

/// Looks for an empty place with the floor.
/// Starting from the `start`, moves in the `direction` till the first floor cell right after the
/// single wall.
/// Returns the found place or null.
fn findPlaceForDoor(self: Dungeon, direction: p.Direction, start: p.Point, region: p.Region) ?p.Point {
    var place = start;
    while (region.containsPoint(place)) {
        if (self.cellAt(place)) |cl| {
            switch (cl) {
                .nothing => {},
                .wall => {
                    if (!self.isCellAt(place.movedTo(direction), .floor)) {
                        return null;
                    }
                    // check that no one door near
                    if (self.isCellAt(place.movedTo(direction.rotatedClockwise(true)), .door)) {
                        return null;
                    }
                    if (self.isCellAt(place.movedTo(direction.rotatedClockwise(false)), .door)) {
                        return null;
                    }
                    return place;
                },
                else => {
                    return null;
                },
            }
        } else {
            return null;
        }
        place.move(direction);
    }
    return null;
}

test "find a place for door inside the room starting outside" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = dungeon.findPlaceForDoor(
        .right,
        p.Point{ .row = 2, .col = 1 },
        region,
    );
    const unexpected = dungeon.findPlaceForDoor(
        .right,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 2 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find a place for door inside the room starting on the wall" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = dungeon.findPlaceForDoor(
        .down,
        p.Point{ .row = 1, .col = 3 },
        region,
    );
    const unexpected = dungeon.findPlaceForDoor(
        .down,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 1, .col = 3 }, expected.?);
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

    var stack_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer stack_arena.deinit();

    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_left = try dungeon.findPlaceForDoorInRegionRnd(&stack_arena, std.crypto.random, region, .left);

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

    var stack_arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer stack_arena.deinit();

    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_bottom = try dungeon.findPlaceForDoorInRegionRnd(&stack_arena, std.crypto.random, region, .down);

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
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const expected_region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = Cols };
    const r1 = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = 6 };
    const r2 = p.Region{ .top_left = .{ .row = 1, .col = 7 }, .rows = Rows, .cols = Cols - 6 };

    // when:
    const region = try dungeon.createAndAddPassageBetweenRegions(std.testing.allocator, std.crypto.random, r1, r2);

    // then:
    try std.testing.expectEqualDeep(expected_region, region);
    const passage: Passage = dungeon.passages.items[0];
    errdefer std.debug.print("Passage: {any}\n", .{passage.turns.items});
    try std.testing.expect(passage.turns.items.len >= 2);
}
