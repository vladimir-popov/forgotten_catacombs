const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.map);

const Map = @This();

pub const rows = g.DISPLAY_ROWS;
pub const cols = g.DISPLAY_COLS;

/// Already visited places in the dungeon.
/// It has only floor cells
visited_places: p.BitMap(g.Dungeon.ROWS, g.Dungeon.COLS),
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMap(p.Point, g.Entity),

pub fn init(alloc: std.mem.Allocator) !Map {
    return .{
        .visited_places = try p.BitMap(g.Dungeon.ROWS, g.Dungeon.COLS).initEmpty(alloc),
        .remembered_objects = std.AutoHashMap(p.Point, g.Entity).init(alloc),
    };
}

pub fn deinit(self: *Map) void {
    self.visited_places.deinit();
    self.remembered_objects.deinit();
}

pub fn clearRetainingCapacity(self: *Map) void {
    self.visited_places.clear();
    self.remembered_objects.clearRetainingCapacity();
}

pub fn addVisitedPlace(self: *Map, visited_place: p.Point) !void {
    try self.visited_places.set(visited_place.row, visited_place.col);
}

pub fn rememberObject(self: *Map, entity: g.Entity, place: p.Point) !void {
    self.remembered_objects.put(place, entity);
}

pub fn forgetObject(self: *Map, place: p.Point) !void {
    _ = try self.remembered_objects.remove(place);
}
