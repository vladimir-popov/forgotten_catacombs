/// This is value object which represents the dungeon as the bitmap for the
/// walls and floor, list of the doors, list of the regions for rooms, and list
/// of the passages.
/// To build the dungeon the `DungeonBuilder` should be used.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.dungeon);

pub const Passage = @import("Passage.zig");

pub const Room = p.Region;

/// Possible types of objects inside the dungeon.
pub const Cell = enum {
    nothing,
    floor,
    wall,
    door,
};

pub const Map = p.BitMap(g.DISPLAY_HEIGHT / g.SPRITE_HEIGHT, g.DISPLAY_WIDHT / g.SPRITE_WIDTH);

pub const ROWS = 40;
pub const COLS = 100;
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

pub fn createMap(self: Dungeon, alloc: std.mem.Allocator) !Map {
    const v_scale = @as(f16, @floatFromInt(Map.rows)) / ROWS;
    const h_scale = @as(f16, @floatFromInt(Map.cols)) / COLS;
    var map = try Map.initEmpty(alloc);
    for (self.rooms.items) |room| {
        var scaled_room = room.scaled(v_scale, h_scale);
        scaleCoordinates(&scaled_room.top_left, v_scale, h_scale);
        map.setRegionValue(scaled_room, true);
    }
    for (self.passages.items) |passage| {
        var itr = passage.places();
        while (itr.next()) |place_in_passage| {
            var place = place_in_passage;
            scaleCoordinates(&place, v_scale, h_scale);
            map.setAt(place);
        }
    }
    return map;
}

fn scaleCoordinates(self: *p.Point, v_scale: f16, h_scale: f16) void {
    self.row = @intFromFloat(@round(v_scale * @as(f16, @floatFromInt(self.row))));
    self.col = @intFromFloat(@round(h_scale * @as(f16, @floatFromInt(self.col))));
    self.row = @max(self.row, 1);
    self.col = @max(self.col, 1);
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
