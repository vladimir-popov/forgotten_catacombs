//! This is the first level of the game
//! with shops and entrance to the dungeon
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const d = @import("dungeon_pkg.zig");

// ╔════════════════════════════════════════╗
// ║########################################║
// ║#..............#  >  #.................#║
// ║#...┌───┐......###+###...........┌───┐.#║
// ║#...│.@.'•••••••••@••••••••••••••+ _ │.#║
// ║#...└───┘••••••••••••••••••••••••└───┘.#║
// ║#...┌───┐••••••••••••••••••••••••......#║
// ║#...│.@.'••••••••••••••••••••••••......#║
// ║#...└───┘••••••••••••••••@•••••••......#║
// ║~~~~~~~~~~~~~~~~~~~~~~~~│<│~~~~~~~~~~~~~║
// ║~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~║
// ║════════════════════════════════════════║
const FirstLocation = @This();

pub const rows = g.DISPLAY_ROWS - 2;
pub const cols = g.DISPLAY_COLS - 1;

const whole_region: p.Region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols };
// The square - place between tents
const square: p.Region = .{ .top_left = .{ .row = 4, .col = 9 }, .rows = 6, .cols = 23 };
/// It leads to the catacombs
const ladder: p.Point = .{ .row = 2, .col = 18 };
const ladder_room: p.Region = .{ .top_left = .{ .row = 1, .col = 15 }, .rows = 3, .cols = 7 };
/// This is the entrance to this level
const wharf: p.Point = .{ .row = 9, .col = 25 };
const traider_tent: p.Region = p.Region{ .top_left = .{ .row = 3, .col = 5 }, .rows = 3, .cols = 5 };
pub const trader_place: p.Point = traider_tent.center();
const scientist_tent: p.Region = p.Region{ .top_left = .{ .row = 6, .col = 5 }, .rows = 3, .cols = 5 };
pub const scientist_place = scientist_tent.center();
const teleport_tent: p.Region = p.Region{ .top_left = .{ .row = 3, .col = 33 }, .rows = 3, .cols = 5 };
pub const teleport_place = teleport_tent.center();

rooms: std.ArrayList(*d.Placement),
doorways: std.AutoHashMap(p.Point, d.Doorway),

pub fn create(arena: *std.heap.ArenaAllocator) !*FirstLocation {
    const alloc = arena.allocator();
    const self = try alloc.create(FirstLocation);
    self.* = .{
        .rooms = std.ArrayList(*d.Placement).init(alloc),
        .doorways = std.AutoHashMap(p.Point, d.Doorway).init(alloc),
    };
    // The whole level room:
    const whole_room = try alloc.create(d.Placement);
    whole_room.* = .{ .room = d.Room.init(alloc, whole_region) };
    try self.rooms.append(whole_room);

    try self.createRoom(alloc, ladder_room, ladder.movedTo(.down));
    try self.createRoom(alloc, traider_tent, traider_tent.bottomRight().movedTo(.up));
    try self.createRoom(alloc, scientist_tent, scientist_tent.bottomRight().movedTo(.up));
    try self.createRoom(alloc, teleport_tent, teleport_tent.top_left.movedTo(.down));

    return self;
}

fn createRoom(self: *FirstLocation, alloc: std.mem.Allocator, region: p.Region, door: p.Point) !void {
    const placement = try alloc.create(d.Placement);
    placement.* = .{ .room = d.Room.init(alloc, region) };
    try self.rooms.append(placement);

    const whole_level = self.rooms.items[0];
    try whole_level.addDoor(door);
    try placement.addDoor(door);
    const doorway = d.Doorway{ .placement_from = whole_level, .placement_to = placement };
    try self.doorways.put(door, doorway);
    try whole_level.room.inner_rooms.append(&placement.room);
}

pub fn dungeon(self: *const FirstLocation) d.Dungeon {
    return .{
        .parent = self,
        .rows = rows,
        .cols = cols,
        .entrance = wharf,
        .exit = ladder,
        .doorways = &self.doorways,
        .vtable = .{
            .cellAtFn = cellAt,
            .placementWithFn = placementWith,
            .randomPlaceFn = randomPlace,
        },
    };
}

fn cellAt(ptr: *const anyopaque, place: p.Point) d.Dungeon.Cell {
    const self: *const FirstLocation = @ptrCast(@alignCast(ptr));

    for (self.rooms.items[1..], 1..) |room, i| {
        if (room.room.region.containsPoint(place)) {
            if (i == 1)
                return replaceWallsByTheRock(cellOfTheRoom(room.room, place))
            else
                return cellOfTheRoom(room.room, place);
        }
    }
    if (place.row == whole_region.bottomRightRow() - 1) {
        if (place.col == wharf.col - 1 or place.col == wharf.col + 1) return .@"│";
        return .water;
    }
    if (place.row > whole_region.bottomRightRow() - 1) {
        return .water;
    }
    return replaceWallsByTheRock(cellOfTheRoom(self.rooms.items[0].room, place));
}

fn cellOfTheRoom(room: d.Room, place: p.Point) d.Dungeon.Cell {
    if (!room.region.containsPoint(place)) return .nothing;

    if (room.doorways.get(place)) |_| return .doorway;

    if (room.region.top_left.row == place.row) {
        if (room.region.top_left.col == place.col) {
            return .@"┌";
        }
        if (room.region.bottomRightCol() == place.col) {
            return .@"┐";
        }
        return .@"─";
    }
    if (room.region.bottomRightRow() == place.row) {
        if (room.region.top_left.col == place.col) {
            return .@"└";
        }
        if (room.region.bottomRightCol() == place.col) {
            return .@"┘";
        }
        return .@"─";
    }
    if (room.region.top_left.col == place.col) {
        return .@"│";
    }
    if (room.region.bottomRightCol() == place.col) {
        return .@"│";
    }
    return .floor;
}

inline fn replaceWallsByTheRock(cell: d.Dungeon.Cell) d.Dungeon.Cell {
    return switch (@intFromEnum(cell)) {
        5...15 => .rock,
        else => cell,
    };
}

fn placementWith(ptr: *const anyopaque, place: p.Point) ?*const d.Placement {
    const self: *const FirstLocation = @ptrCast(@alignCast(ptr));

    for (self.rooms.items[1..]) |room| {
        if (room.room.region.containsPoint(place)) {
            return room;
        }
    }
    return self.rooms.items[0];
}

fn randomPlace(_: *const anyopaque, rand: std.Random) p.Point {
    return .{
        .row = square.top_left.row + rand.uintLessThan(u8, square.rows - 2) + 1,
        .col = square.top_left.col + rand.uintLessThan(u8, square.cols - 2) + 1,
    };
}
