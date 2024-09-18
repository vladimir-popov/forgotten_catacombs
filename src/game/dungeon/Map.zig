const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.map);

const Room = p.Region;

const Map = @This();

pub const rows = g.DISPLAY_ROWS;
pub const cols = g.DISPLAY_COLS;

const v_scale = @as(f16, @floatFromInt(rows)) / g.Dungeon.ROWS;
const h_scale = @as(f16, @floatFromInt(cols)) / g.Dungeon.COLS;

/// Already visited rooms. The rooms should be marked as visited entirely.
visited_rooms: std.ArrayList(Room),
/// Already visited places in passages. Some points can mapped to the same visited points because of scaling.
visited_places: std.AutoHashMap(p.Point, void),
/// Already visited doors
visited_doors: std.ArrayList(p.Point),
room_with_entrance: ?usize = null,
room_with_exit: ?usize = null,

pub fn init(alloc: std.mem.Allocator) Map {
    return .{
        .visited_rooms = std.ArrayList(Room).init(alloc),
        .visited_places = std.AutoHashMap(p.Point, void).init(alloc),
        .visited_doors = std.ArrayList(p.Point).init(alloc),
    };
}

pub fn deinit(self: *Map) void {
    self.visited_rooms.deinit();
    self.visited_places.deinit();
    self.visited_doors.deinit();
}

pub fn addVisitedRoom(self: *Map, visited_room: Room, has_entrance: bool, has_exit: bool) !void {
    const room = try self.visited_rooms.addOne();
    room.* = visited_room.scaled(1.1 * v_scale, h_scale);
    scaleCoordinates(&room.top_left);
    if (has_entrance) self.room_with_entrance = self.visited_rooms.items.len - 1;
    if (has_exit) self.room_with_exit = self.visited_rooms.items.len - 1;
}

pub fn addVisitedPlace(self: *Map, visited_place: p.Point) !void {
    try self.visited_places.put(scaledPoint(visited_place), {});
}

pub fn addVisitedDoor(self: *Map, visited_door: p.Point) !void {
    const door = try self.visited_doors.addOne();
    door.* = visited_door;
    scaleCoordinates(door);
}

pub fn scaledPoint(point: p.Point) p.Point {
    var pt = point;
    scaleCoordinates(&pt);
    return pt;
}

fn scaleCoordinates(self: *p.Point) void {
    self.row = @intFromFloat(@round(v_scale * @as(f16, @floatFromInt(self.row))));
    self.col = @intFromFloat(@round(h_scale * @as(f16, @floatFromInt(self.col))));
    self.row = @max(self.row, 1);
    self.col = @max(self.col, 1);
}
