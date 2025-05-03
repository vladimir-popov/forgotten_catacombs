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

area: d.Area,
/// Index of all doorways by their place
doorways: std.AutoHashMapUnmanaged(p.Point, d.Doorway),

pub fn generateDungeon(arena: *std.heap.ArenaAllocator) !d.Dungeon {
    const alloc = arena.allocator();
    const first_location = try alloc.create(FirstLocation);
    first_location.* = .{
        .area = d.Area.init(arena, whole_region),
        .doorways = .empty,
    };

    try first_location.createRoom(alloc, ladder_room, ladder.movedTo(.down));
    try first_location.createRoom(alloc, traider_tent, traider_tent.bottomRight().movedTo(.up));
    try first_location.createRoom(alloc, scientist_tent, scientist_tent.bottomRight().movedTo(.up));
    try first_location.createRoom(alloc, teleport_tent, teleport_tent.top_left.movedTo(.down));
    // the pointer to the first_location will be removed on arena.deinit
    return first_location.dungeon();
}

fn createRoom(self: *FirstLocation, alloc: std.mem.Allocator, region: p.Region, door: p.Point) !void {
    const doorway = d.Doorway{
        .placement_from = .{ .area = &self.area },
        .placement_to = .{ .room = try self.area.addRoom(region, door) },
    };
    try self.doorways.put(alloc, door, doorway);
}

fn dungeon(self: *FirstLocation) d.Dungeon {
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

    for (self.area.inner_rooms.items, 0..) |room, i| {
        if (room.region.containsPoint(place)) {
            // the room with ladder down should be part of the cave
            if (i == 0) {
                if (room.doorways.get(place)) |_| return .doorway;
                return floorOrRock(room.region, place);
            } else {
                return cellForTheTent(room, place);
            }
        }
    }
    if (place.row == whole_region.bottomRightRow() - 1) {
        if (place.col == wharf.col - 1 or place.col == wharf.col + 1) return .@"│";
        return .water;
    }
    if (place.row > whole_region.bottomRightRow() - 1) {
        return .water;
    }
    return floorOrRock(self.area.region, place);
}

fn floorOrRock(region: p.Region, place: p.Point) d.Dungeon.Cell {
    if (!region.containsPoint(place)) return .nothing;

    if (place.row == region.top_left.row or place.row == region.bottomRightRow()) {
        return .rock;
    }
    if (place.col == region.top_left.col or place.col == region.bottomRightCol()) {
        return .rock;
    }
    return .floor;
}

fn cellForTheTent(room: *const d.Room, place: p.Point) d.Dungeon.Cell {
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
        1...11 => .rock,
        else => cell,
    };
}

fn placementWith(ptr: *anyopaque, place: p.Point) ?d.Placement {
    const self: *FirstLocation = @ptrCast(@alignCast(ptr));

    for (self.area.inner_rooms.items) |room| {
        if (room.region.containsPoint(place)) {
            return .{ .room = room };
        }
    }
    return .{ .area = &self.area };
}

fn randomPlace(_: *const anyopaque, rand: std.Random) p.Point {
    return .{
        .row = square.top_left.row + rand.uintLessThan(u8, square.rows - 2) + 1,
        .col = square.top_left.col + rand.uintLessThan(u8, square.cols - 2) + 1,
    };
}
