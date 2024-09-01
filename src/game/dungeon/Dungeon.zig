const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

pub const Passage = @import("Passage.zig");

pub const Room = p.Region;

/// Possible types of objects inside the dungeon.
pub const Cell = enum {
    nothing,
    floor,
    wall,
    door,
};

pub const ROWS = 40;
pub const COLS = 100;
pub const REGION: p.Region = .{
    .top_left = .{ .row = 1, .col = 1 },
    .rows = ROWS,
    .cols = COLS,
};


const BitMap = p.BitMap(ROWS, COLS);

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
floor: BitMap,
/// The bit mask of the places with walls. The floor under the walls is undefined, it can be, or can be omitted.
walls: BitMap,

/// Creates an empty dungeon.
pub fn init(alloc: std.mem.Allocator) !Dungeon {
    return .{
        .alloc = alloc,
        .floor = try BitMap.initEmpty(alloc),
        .walls = try BitMap.initEmpty(alloc),
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

pub inline fn containsPlace(self: Dungeon, place: p.Point) bool {
    return self.Region.containsPoint(place);
}

pub inline fn cellAt(self: Dungeon, place: p.Point) ?Cell {
    if (place.row < 1 or place.row > ROWS) {
        return null;
    }
    if (place.col < 1 or place.col > COLS) {
        return null;
    }
    if (self.walls.isSet(place.row, place.col)) {
        return .wall;
    }
    if (self.floor.isSet(place.row, place.col)) {
        return .floor;
    }
    if (self.doors.get(place)) |_| {
        return .door;
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
        if (!REGION.containsPoint(self.current_place))
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

pub fn cellsInRegion(self: Dungeon, region: p.Region) ?CellsIterator {
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
    const dungeon = try Dungeon.init(alloc);
    try dungeon.floor.parse('.', str);
    try dungeon.walls.parse('#', str);
    return dungeon;
}

/// Removes doors, floor and walls on the passed place.
pub fn cleanAt(dungeon: *Dungeon, place: p.Point) void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    dungeon.floor.unsetAt(place);
    dungeon.walls.unsetAt(place);
    _ = dungeon.doors.remove(place);
}

/// Removes doors, floor and walls on the passed place, and create a new door.
pub fn forceCreateFloorAt(dungeon: *Dungeon, place: p.Point) !void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    dungeon.cleanAt(place);
    dungeon.floor.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a new wall.
pub fn forceCreateWallAt(dungeon: *Dungeon, place: p.Point) !void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    dungeon.cleanAt(place);
    dungeon.walls.setAt(place);
}

/// Removes doors, floor and walls on the passed place, and create a cell with floor.
pub fn forceCreateDoorAt(dungeon: *Dungeon, place: p.Point) !void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    dungeon.cleanAt(place);
    try dungeon.doors.put(place, {});
}

/// Creates the cell with wall only if nothing exists on the passed place.
fn createWallAt(dungeon: *Dungeon, place: p.Point) void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    if (dungeon.isCellAt(place, .nothing)) {
        dungeon.walls.setAt(place);
    }
}

/// Creates the cell with floor only if nothing exists on the passed place.
pub fn createFloorAt(dungeon: *Dungeon, place: p.Point) void {
    if (!dungeon.containsPlace(place)) {
        return;
    }
    if (dungeon.isCellAt(place, .nothing)) {
        dungeon.floor.setAt(place);
    }
}
