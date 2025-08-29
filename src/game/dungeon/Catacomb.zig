//! The Catacomb level. Catacombs are part of the shelter.
//! They represent set of rooms connected by passages.
const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;
const plc = @import("placements.zig");
const u = g.utils;

const BspTree = @import("BspTree.zig");
const Catacomb = @import("Catacomb.zig");
const Dungeon = @import("Dungeon.zig");

const Placement = plc.Placement;
const Doorway = plc.Doorway;
const Room = plc.Room;
const Passage = plc.Passage;

const log = std.log.scoped(.bsp_dungeon);

pub const rows = 3 * g.DISPLAY_ROWS;
pub const cols = 3 * g.DISPLAY_COLS;

pub const Error = error{
    NoSpaceForDoor,
    PassageCantBeCreated,
    PlaceOutsideTheDungeon,
    RoomWasNotFound,
};

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

const Self = @This();

/// Used to allocate placements of this catacomb
arena: std.heap.ArenaAllocator,
opts: Options,
/// The index over all placements in the dungeon.
// we can't store the placements in the array, because of invalidation of the
// inner state of the array
placements: std.ArrayListUnmanaged(Placement),
/// Index of all doorways by their place
doorways: std.AutoHashMapUnmanaged(p.Point, Doorway),
/// The bit mask of the places with floor.
floor: u.BitMap(rows, cols),
/// The bit mask of the places with walls. The floor under the walls is undefined, it can be set, or can be omitted.
walls: u.BitMap(rows, cols),

/// Uses arena to create a self instance and a dungeon with passed seed.
pub fn generateDungeon(arena: *std.heap.ArenaAllocator, opts: Options, seed: u64) !d.Dungeon {
    const alloc = arena.allocator();
    const self = try alloc.create(Self);
    try self.init(alloc, opts);
    return try self.dungeon(seed);
}

/// Allocates an instance with passed arena allocator, and initializes all inner state.
pub fn init(self: *Self, alloc: std.mem.Allocator, opts: Options) !void {
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .opts = opts,
        .placements = std.ArrayListUnmanaged(Placement){},
        .doorways = std.AutoHashMapUnmanaged(p.Point, Doorway){},
        .floor = try u.BitMap(rows, cols).initEmpty(self.arena.allocator()),
        .walls = try u.BitMap(rows, cols).initEmpty(self.arena.allocator()),
    };
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

/// Creates the dungeon with BSP algorithm.
pub fn dungeon(self: *Self, seed: u64) !d.Dungeon {
    var prng = std.Random.DefaultPrng.init(seed);
    const rand = prng.random();

    // this arena is used to build a BSP tree, which can be destroyed
    // right after completing the dungeon.
    var bsp_arena = std.heap.ArenaAllocator.init(self.arena.allocator());
    defer _ = bsp_arena.deinit();

    // BSP helps to mark regions for rooms without intersections
    const root = try BspTree.build(
        &bsp_arena,
        rand,
        // g.DUNGEON_ROWS,
        // g.DUNGEON_COLS,
        rows,
        cols,
        .{
            .min_rows = self.opts.region_min_rows,
            .min_cols = self.opts.region_min_cols,
            .square_ratio = self.opts.square_ratio,
        },
    );

    // visit every BSP node and generate rooms in the leafs
    var createRooms: TraverseAndCreateRooms = .{
        .dungeon = self,
        .rand = rand,
    };
    try root.traverse(&bsp_arena, createRooms.handler());
    log.debug("The rooms have been created", .{});

    // fold the BSP tree and binds nodes with the same parent:
    var createPassages: CreatePassageBetweenRegions = .{
        .dungeon = self,
        .rand = rand,
    };
    _ = try root.foldModify(&bsp_arena, createPassages.handler());
    log.debug("The passages have been created", .{});

    return .{
        .seed = seed,
        .type = .catacomb,
        .parent = self,
        .rows = rows,
        .cols = cols,
        .entrance = (try self.firstRoom()).randomPlace(rand),
        .exit = (try self.lastRoom()).randomPlace(rand),
        .doorways = &self.doorways,
        .vtable = .{
            .cellAtFn = cellAtFn,
            .placementWithFn = findPlacementWith,
            .randomPlaceFn = randomPlace,
        },
    };
}

const TraverseAndCreateRooms = struct {
    dungeon: *Catacomb,
    rand: std.Random,

    fn handler(self: *TraverseAndCreateRooms) BspTree.Node.TraverseHandler {
        return .{ .ptr = self, .handle = TraverseAndCreateRooms.createRoom };
    }

    fn createRoom(ptr: *anyopaque, node: *BspTree.Node) anyerror!void {
        if (!node.isLeaf()) return;
        const self: *TraverseAndCreateRooms = @ptrCast(@alignCast(ptr));
        const region_for_room = try createRandomRegionInside(node.value, self.rand, self.dungeon.opts);
        try self.dungeon.generateAndAddRoom(region_for_room);
    }
};

const CreatePassageBetweenRegions = struct {
    dungeon: *Catacomb,
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

fn cellAtFn(ptr: *const anyopaque, place: p.Point) Dungeon.Cell {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    return self.cellAt(place);
}

fn cellAt(self: *const Self, place: p.Point) Dungeon.Cell {
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

inline fn isCellAt(self: Self, place: p.Point, assumption: Dungeon.Cell) bool {
    return self.cellAt(place) == assumption;
}

pub fn findPlacementWith(ptr: *const anyopaque, place: p.Point) ?Placement {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    for (self.placements.items) |placement| {
        if (placement.contains(place)) {
            return placement;
        }
    }
    return null;
}

pub fn firstRoom(self: Self) Error!*Room {
    for (self.placements.items) |placement| {
        switch (placement) {
            .room => |room| return room,
            else => {},
        }
    }
    return Error.RoomWasNotFound;
}

pub fn lastRoom(self: Self) Error!*Room {
    var i: usize = self.placements.items.len - 1;
    while (i >= 0) : (i -= 1) {
        switch (self.placements.items[i]) {
            .room => |room| return room,
            else => {},
        }
    }
}

fn randomPlace(ptr: *const anyopaque, rand: std.Random) p.Point {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    const placement = self.placements.items[rand.uintLessThan(usize, self.placements.items.len)];
    return placement.randomPlace(rand);
}

fn findPlacement(self: Self, place: p.Point) !Placement {
    for (self.placements.items) |placement| {
        if (placement.contains(place)) return placement;
    }
    log.err("No one placement was found with {any}", .{place});
    return Error.PlaceOutsideTheDungeon;
}

/// For tests only
pub fn parse(arena: *std.heap.ArenaAllocator, str: []const u8) !Self {
    if (!@import("builtin").is_test) {
        @compileError("The function `parse` is for test purpose only");
    }
    var catacomb: Self = undefined;
    try catacomb.init(arena.allocator(), .{});
    try catacomb.floor.parse('.', str);
    try catacomb.walls.parse('#', str);
    return catacomb;
}

// ==================================================
//       Methods for modification.
//       Usually used by the dungeon generators.
// ==================================================

pub fn generateAndAddRoom(self: *Self, region: p.Region) !void {
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
    try self.placements.append(self.arena.allocator(), .{ .room = try Placement.createRoom(&self.arena, region) });
}

inline fn addEmptyPassage(self: *Self) !*Passage {
    const passage = try Placement.createPassage(&self.arena);
    try self.placements.append(self.arena.allocator(), .{ .passage = passage });
    return passage;
}

/// Finds a place for a door on the borders of the region r1 and region 2, and create a passage
/// between. Return a region included both passed regions and created passage.
pub fn createAndAddPassageBetweenRegions(
    self: *Self,
    rand: std.Random,
    r1: p.Region,
    r2: p.Region,
) !p.Region {
    var stack_arena = std.heap.ArenaAllocator.init(self.arena.allocator());
    defer _ = stack_arena.deinit();

    const direction: p.Direction = if (r1.top_left.row == r2.top_left.row) .right else .down;
    const doorPlace1 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r1, direction) orelse {
        log.err("A place for door was not found in {any} in {s} direction", .{ r1, @tagName(direction) });
        return Error.NoSpaceForDoor;
    };
    const doorPlace2 = try self.findPlaceForDoorInRegionRnd(&stack_arena, rand, r2, direction.opposite()) orelse {
        log.err("A place for door was not found in {any} in {s} direction", .{ r2, @tagName(direction.opposite()) });
        return Error.NoSpaceForDoor;
    };

    const passage = try self.addEmptyPassage();

    log.debug("Found places for doors: {any}; {any}. Prepare the passage between them...", .{ doorPlace1, doorPlace2 });
    _ = try passage.turnAt(self.arena.allocator(), doorPlace1, direction);
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

        _ = try passage.turnToPoint(self.arena.allocator(), middle1, middle2);
        _ = try passage.turnToPoint(self.arena.allocator(), middle2, doorPlace2);
    }
    _ = try passage.turnAt(self.arena.allocator(), doorPlace2, direction);
    log.debug("The passage was prepared: {any}", .{passage});

    try self.digPassage(passage);
    const placement1 = try self.findPlacement(doorPlace1.movedTo(direction.opposite()));
    try self.forceCreateDoorBetween(
        .{ .passage = passage },
        placement1,
        doorPlace1,
    );
    const placement2 = try self.findPlacement(doorPlace2.movedTo(direction));
    try self.forceCreateDoorBetween(
        .{ .passage = passage },
        placement2,
        doorPlace2,
    );

    return r1.unionWith(r2);
}

/// Removes doors, floor and walls on the passed place.
pub fn cleanAt(self: *Self, place: p.Point) void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    if (self.doorways.contains(place)) std.debug.panic("Impossible to remove the door at {any}", .{place});
    self.floor.unsetAt(place);
    self.walls.unsetAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new door.
pub fn forceCreateFloorAt(self: *Self, place: p.Point) !void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.floor.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new wall.
pub fn forceCreateWallAt(self: Self, place: p.Point) !void {
    if (!Self.REGION.containsPoint(place)) {
        return;
    }
    self.cleanAt(place);
    self.walls.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a cell with floor.
pub fn forceCreateDoorBetween(
    self: *Self,
    placement_from: Placement,
    placement_to: Placement,
    place: p.Point,
) !void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return Error.PlaceOutsideTheDungeon;
    }
    self.cleanAt(place);
    const doorway = Doorway{ .placement_from = placement_from, .placement_to = placement_to };
    try self.doorways.put(self.arena.allocator(), place, doorway);
    try placement_from.addDoor(&self.arena, place);
    try placement_to.addDoor(&self.arena, place);
    log.debug("Created {any} at {any}", .{ doorway, place });
}

/// Creates the cell with wall only if nothing exists on the passed place.
fn createWallAt(self: *Self, place: p.Point) void {
    if (!g.DUNGEON_REGION.containsPoint(place)) {
        return;
    }
    if (self.isCellAt(place, .nothing)) {
        self.walls.setAt(place);
    }
}

/// Creates the cell with floor only if nothing exists on the passed place.
pub fn createFloorAt(self: *Self, place: p.Point) void {
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
    self: Self,
    stack_arena: *std.heap.ArenaAllocator,
    init_from: p.Point,
    init_to: p.Point,
    is_horizontal: bool,
    attempt: u8,
) !?struct { p.Point, p.Point } {
    const MAX_ATTEMPTS = 5;
    // to prevent infinite loop
    var current_attempt = attempt;
    const alloc = stack_arena.allocator();
    var stack: std.ArrayList(struct { p.Point, p.Point }) = .empty;
    try stack.append(alloc, .{ init_from, init_to });
    var middle1: p.Point = undefined;
    var middle2: p.Point = undefined;
    while (stack.pop()) |points| {
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
            try stack.append(alloc, .{ from, middle2 });
            try stack.append(alloc, .{ middle1, to });
        }
    }
    return null;
}

fn isFreeLine(self: Self, from: p.Point, to: p.Point) bool {
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

fn digPassage(self: *Self, passage: *const Passage) !void {
    var prev: Passage.Turn = passage.turns.items[0];
    for (passage.turns.items[1 .. passage.turns.items.len - 1]) |turn| {
        try self.dig(prev.place, turn.place, prev.to_direction);
        try self.digTurn(turn.place, prev.to_direction, turn.to_direction);
        prev = turn;
    }
    try self.dig(prev.place, passage.turns.getLast().place, prev.to_direction);
}

fn dig(self: *Self, from: p.Point, to: p.Point, direction: p.Direction) !void {
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

fn digTurn(self: *Self, at: p.Point, from: p.Direction, to: p.Direction) !void {
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
    self: Self,
    stack_arena: *std.heap.ArenaAllocator,
    rand: std.Random,
    init_region: p.Region,
    side: p.Direction,
) !?p.Point {
    const alloc = stack_arena.allocator();
    var stack: std.ArrayList(p.Region) = .empty;
    try stack.append(alloc, init_region);
    while (stack.pop()) |region| {
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
                try stack.append(alloc, reg);
            }
        }
    }
    return null;
}

/// Looks for an empty place with the floor.
/// Starting from the `start`, moves in the `direction` till the first floor cell right after the
/// single wall.
/// Returns the found place or null.
fn findPlaceForDoor(self: Self, direction: p.Direction, start: p.Point, region: p.Region) ?p.Point {
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
    var dung = try Self.parse(&arena, str);
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
    var dung = try Self.parse(&arena, str);
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
    var dung = try Self.parse(&arena, str);
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
    var dung = try Self.parse(&arena, str);
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
    const str =
        \\ ####   ####
        \\ #..#   #..#
        \\ #..#   #..#
        \\ ####   ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var dung = try Self.parse(&arena, str);
    const room1 = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 4 };
    const room2 = p.Region{ .top_left = .{ .row = 1, .col = 7 }, .rows = 4, .cols = 4 };
    _ = try dung.generateAndAddRoom(room1);
    _ = try dung.generateAndAddRoom(room2);

    const expected_region = room1.unionWith(room2);

    // when:
    const region = try dung.createAndAddPassageBetweenRegions(std.crypto.random, room1, room2);

    // then:
    try std.testing.expectEqualDeep(expected_region, region);
    const passage = dung.placements.items[2].passage;
    errdefer std.debug.print("Passage: {any}\n", .{passage.turns.items});
    try std.testing.expect(passage.turns.items.len >= 2);
}

test "For same seed should return same dungeon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buf_expected: [10000]u8 = undefined;
    var buf_actual: [10000]u8 = undefined;

    const seed = 100500;
    var previous = try generateAndWriteDungeon(&arena, &buf_expected, seed);

    for (0..10) |_| {
        const current = try generateAndWriteDungeon(&arena, &buf_actual, seed);
        try std.testing.expectEqualStrings(previous, current);
        previous = current;
    }
}

fn generateAndWriteDungeon(arena: *std.heap.ArenaAllocator, buf: []u8, seed: u64) ![]const u8 {
    var bfw = std.io.fixedBufferStream(buf);
    const dunge = try Self.generateDungeon(arena, .{}, seed);
    const len = try dunge.write(bfw.writer());
    return buf[0..len];
}
