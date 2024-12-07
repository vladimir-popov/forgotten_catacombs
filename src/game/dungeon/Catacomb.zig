//! The Catacomb level. Catacombs are part of the shelter.
//! They represent set of rooms connected by passages.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const placements = @import("placements.zig");
const Dungeon = @import("Dungeon.zig");

const Placement = placements.Placement;
const Doorway = placements.Doorway;
const Room = placements.Room;
const Passage = placements.Passage;

const log = std.log.scoped(.bsp_dungeon);

pub const Error = error{
    NoSpaceForDoor,
    PassageCantBeCreated,
    PlaceOutsideTheDungeon,
    RoomWasNotFound,
};

/// 36
const rows = g.DUNGEON_ROWS;
/// 120
const cols = g.DUNGEON_COLS;

const Catacomb = @This();

arena: *std.heap.ArenaAllocator,
arena_alloc: std.mem.Allocator,
/// The index over all placements in the dungeon.
// we can't store the placements in the array, because of invalidation of the
// inner state of the array
placements: std.ArrayList(*Placement),
/// Index of all doorways by their place
doorways: std.AutoHashMap(p.Point, Doorway),
/// The bit mask of the places with floor.
floor: p.BitMap(rows, cols),
/// The bit mask of the places with walls. The floor under the walls is undefined, it can be set, or can be omitted.
walls: p.BitMap(rows, cols),
entrance: p.Point = undefined,
exit: p.Point = undefined,

/// Allocates an empty dungeon, and initializes all inner state with passed arena
/// allocator. The returned instance should be additionally initialized by the
/// CatacombGenerator. All memory can be freed by deinit arena.
pub fn create(arena: *std.heap.ArenaAllocator) !*Catacomb {
    const arena_alloc = arena.allocator();
    const self = try arena_alloc.create(Catacomb);
    self.* = .{
        .arena = arena,
        .arena_alloc = arena_alloc,
        .placements = std.ArrayList(*Placement).init(arena_alloc),
        .doorways = std.AutoHashMap(p.Point, Doorway).init(arena_alloc),
        .floor = try p.BitMap(rows, cols).initEmpty(arena_alloc),
        .walls = try p.BitMap(rows, cols).initEmpty(arena_alloc),
    };
    return self;
}

pub fn dungeon(self: *const Catacomb) Dungeon {
    return .{
        .parent = self,
        .rows = rows,
        .cols = cols,
        .entrance = self.entrance,
        .exit = self.exit,
        .doorways = &self.doorways,
        .vtable = .{
            .cellAtFn = cellAtFn,
            .placementWithFn = findPlacementWith,
            .randomPlaceFn = randomPlace,
        },
    };
}

fn cellAtFn(ptr: *const anyopaque, place: p.Point) Dungeon.Cell {
    const self: *const Catacomb = @ptrCast(@alignCast(ptr));
    return self.cellAt(place);
}

fn cellAt(self: *const Catacomb, place: p.Point) Dungeon.Cell {
    if (place.row < 1 or place.row > rows) {
        return .nothing;
    }
    if (place.col < 1 or place.col > cols) {
        return .nothing;
    }
    if (self.walls.isSet(place.row, place.col)) {
        return .wall;
    }
    if (self.floor.isSet(place.row, place.col)) {
        return .floor;
    }
    if (self.doorways.contains(place)) {
        return .doorway;
    }
    return .nothing;
}

inline fn isCellAt(self: Catacomb, place: p.Point, assumption: Dungeon.Cell) bool {
    return self.cellAt(place) == assumption;
}

pub fn findPlacementWith(ptr: *const anyopaque, place: p.Point) ?*const Placement {
    const self: *const Catacomb = @ptrCast(@alignCast(ptr));
    for (self.placements.items) |placement| {
        if (placement.contains(place)) {
            return placement;
        }
    }
    return null;
}

pub fn firstRoom(self: Catacomb) Error!Room {
    for (self.placements.items) |placement| {
        switch (placement.*) {
            .room => |room| return room,
            else => {},
        }
    }
    return Error.RoomWasNotFound;
}

pub fn lastRoom(self: Catacomb) Error!Room {
    var i: usize = self.placements.items.len - 1;
    while (i >= 0) : (i -= 1) {
        switch (self.placements.items[i].*) {
            .room => |room| return room,
            else => {},
        }
    }
}

fn randomPlace(ptr: *const anyopaque, rand: std.Random) p.Point {
    const self: *const Catacomb = @ptrCast(@alignCast(ptr));
    const placement = self.placements.items[rand.uintLessThan(usize, self.placements.items.len)];
    switch (placement.*) {
        .room => |room| return room.randomPlace(rand),
        .passage => |passage| return passage.randomPlace(rand),
    }
}

fn findPlacement(self: Catacomb, place: p.Point) !*Placement {
    for (self.placements.items) |placement| {
        if (placement.contains(place)) return placement;
    }
    log.err("No one placement was found with {any}", .{place});
    self.dungeon().dumpToLog();
    return Error.PlaceOutsideTheDungeon;
}

/// For tests only
pub fn parse(arena: *std.heap.ArenaAllocator, str: []const u8) !Catacomb {
    if (!@import("builtin").is_test) {
        @compileError("The function `parse` is for test purpose only");
    }
    var dung = try Catacomb.create(arena);
    try dung.floor.parse('.', str);
    try dung.walls.parse('#', str);
    return dung;
}

// ==================================================
//       Methods for modification.
//       Usually used by the dungeon generators.
// ==================================================

pub fn generateAndAddRoom(self: *Catacomb, region: p.Region) !void {
    // generate walls:
    for (region.top_left.row..(region.top_left.row + region.rows)) |r| {
        if (r == region.top_left.row or r == region.bottomRightRow()) {
            self.walls.setRowValue(@intCast(r), region.top_left.col, region.cols, true);
        } else {
            self.walls.set(@intCast(r), @intCast(region.top_left.col));
            self.walls.set(@intCast(r), @intCast(region.bottomRightCol()));
        }
    }
    // generate floor:
    self.floor.setRegionValue(region, true);
    const placement = try self.arena_alloc.create(Placement);
    placement.* = .{ .room = Room.init(self.arena_alloc, region) };
    try self.placements.append(placement);
}

inline fn addEmptyPassage(self: *Catacomb) !*Placement {
    const pl = try self.arena_alloc.create(Placement);
    pl.* = .{ .passage = Passage.init(self.arena_alloc) };
    try self.placements.append(pl);
    return pl;
}

pub fn createAndAddPassageBetweenRegions(
    self: *Catacomb,
    rand: std.Random,
    r1: p.Region,
    r2: p.Region,
) !p.Region {
    var stack_arena = std.heap.ArenaAllocator.init(self.arena_alloc);
    defer _ = stack_arena.deinit();

    const direction: p.Direction = if (r1.top_left.row == r2.top_left.row) .right else .down;
    const doorPlace1 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r1, direction) orelse
        return Error.NoSpaceForDoor;
    const doorPlace2 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r2, direction.opposite()) orelse
        return Error.NoSpaceForDoor;

    const passage = try self.addEmptyPassage();

    log.debug("Found places for doors: {any}; {any}. Prepare the passage between them...", .{ doorPlace1, doorPlace2 });
    _ = try passage.passage.turnAt(doorPlace1, direction);
    if (doorPlace1.row != doorPlace2.row and doorPlace1.col != doorPlace2.col) {
        // intersection of the passage from the door 1 and region 1
        var middle1: p.Point = if (direction.isHorizontal())
            // left or right
            .{ .row = doorPlace1.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = doorPlace1.col };

        // intersection of the passage from the region 1 and door 2
        var middle2: p.Point = if (direction.isHorizontal())
            // left or right
            .{ .row = doorPlace2.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = doorPlace2.col };

        // try to find better places for turn:
        if (try self.findPlaceForPassageTurn(&stack_arena, doorPlace1, doorPlace2, direction.isHorizontal(), 0)) |places| {
            middle1 = places[0];
            middle2 = places[1];
        }

        _ = try passage.passage.turnToPoint(middle1, middle2);
        _ = try passage.passage.turnToPoint(middle2, doorPlace2);
    }
    _ = try passage.passage.turnAt(doorPlace2, direction);
    log.debug("The passage was prepared: {any}", .{passage});

    try self.digPassage(passage.passage);
    const placement1 = try self.findPlacement(doorPlace1.movedTo(direction.opposite()));
    try self.forceCreateDoorBetween(
        passage,
        placement1,
        doorPlace1,
    );
    const placement2 = try self.findPlacement(doorPlace2.movedTo(direction));
    try self.forceCreateDoorBetween(
        passage,
        placement2,
        doorPlace2,
    );

    return r1.unionWith(r2);
}

/// Removes doors, floor and walls on the passed place.
pub fn cleanAt(self: *Catacomb, place: p.Point) void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    if (self.doorways.contains(place)) std.debug.panic("Impossible to remove the door at {any}", .{place});
    self.floor.unsetAt(place);
    self.walls.unsetAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new door.
pub fn forceCreateFloorAt(self: *Catacomb, place: p.Point) !void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.floor.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new wall.
pub fn forceCreateWallAt(self: Catacomb, place: p.Point) !void {
    if (!Catacomb.REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.walls.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a cell with floor.
pub fn forceCreateDoorBetween(
    self: *Catacomb,
    placement_from: *Placement,
    placement_to: *Placement,
    place: p.Point,
) !void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return Error.PlaceOutsideTheDungeon;
    }
    self.cleanAt(place);
    const door = Doorway{ .placement_from = placement_from, .placement_to = placement_to };
    try self.doorways.put(place, door);
    try placement_from.addDoor(place);
    try placement_to.addDoor(place);
    log.debug("Created {any} at {any}", .{ door, place });
}

/// Creates the cell with wall only if nothing exists on the passed place.
fn createWallAt(self: *Catacomb, place: p.Point) void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    if (self.isCellAt(place, .nothing)) {
        self.walls.setAt(place);
    }
}

/// Creates the cell with floor only if nothing exists on the passed place.
pub fn createFloorAt(self: *Catacomb, place: p.Point) void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    if (self.isCellAt(place, .nothing)) {
        self.floor.setAt(place);
    }
}

/// Trying to find a line between `from` and `to` with `nothing` cells only.
/// Gives up after MAX_ATTEMPTS attempts to prevent long search.
fn findPlaceForPassageTurn(
    self: Catacomb,
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

fn isFreeLine(self: Catacomb, from: p.Point, to: p.Point) bool {
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

fn digPassage(self: *Catacomb, passage: Passage) !void {
    var prev: Passage.Turn = passage.turns.items[0];
    for (passage.turns.items[1 .. passage.turns.items.len - 1]) |turn| {
        try self.dig(prev.place, turn.place, prev.to_direction);
        try self.digTurn(turn.place, prev.to_direction, turn.to_direction);
        prev = turn;
    }
    try self.dig(prev.place, passage.turns.getLast().place, prev.to_direction);
}

fn dig(self: *Catacomb, from: p.Point, to: p.Point, direction: p.Direction) !void {
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

fn digTurn(self: *Catacomb, at: p.Point, from: p.Direction, to: p.Direction) !void {
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
    self: Catacomb,
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
            switch (self.cellAt(candidate)) {
                .wall => {
                    return candidate;
                },
                else => {},
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
fn findPlaceForDoor(self: Catacomb, direction: p.Direction, start: p.Point, region: p.Region) ?p.Point {
    var place = start;
    while (region.containsPoint(place)) {
        switch (self.cellAt(place)) {
            .nothing => {},
            .wall => {
                if (!self.isCellAt(place.movedTo(direction), .floor)) {
                    return null;
                }
                // check that no one door near
                if (self.isCellAt(place.movedTo(direction.rotatedClockwise(true)), .doorway)) {
                    return null;
                }
                if (self.isCellAt(place.movedTo(direction.rotatedClockwise(false)), .doorway)) {
                    return null;
                }
                return place;
            },
            else => return null,
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Catacomb.parse(&arena, str);
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = dung.findPlaceForDoor(
        .right,
        p.Point{ .row = 2, .col = 1 },
        region,
    );
    const unexpected = dung.findPlaceForDoor(
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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Catacomb.parse(&arena, str);
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = dung.findPlaceForDoor(
        .down,
        p.Point{ .row = 1, .col = 3 },
        region,
    );
    const unexpected = dung.findPlaceForDoor(
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

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Catacomb.parse(&arena, str);
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_left = try dung.findPlaceForDoorInRegionRnd(&stack_arena, std.crypto.random, region, .left);

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

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Catacomb.parse(&arena, str);
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_bottom = try dung.findPlaceForDoorInRegionRnd(&stack_arena, std.crypto.random, region, .down);

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
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Catacomb.parse(&arena, str);
    _ = try dung.addRoom(.{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = 4 });
    _ = try dung.addRoom(.{ .top_left = .{ .row = 1, .col = 7 }, .rows = Rows, .cols = 4 });

    const expected_region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = Cols };
    // regions with rooms:
    const r1 = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = 6 };
    const r2 = p.Region{ .top_left = .{ .row = 1, .col = 7 }, .rows = Rows, .cols = Cols - 6 };

    // when:
    const region = try dung.createAndAddPassageBetweenRegions(std.crypto.random, r1, r2);

    // then:
    try std.testing.expectEqualDeep(expected_region, region);
    const passage: Passage = dung.placements.items[2].passage;
    errdefer std.debug.print("Passage: {any}\n", .{passage.turns.items});
    try std.testing.expect(passage.turns.items.len >= 2);
}
