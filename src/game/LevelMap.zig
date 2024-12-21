const std = @import("std");
const g = @import("game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.level_map);

const LevelMap = @This();

rows: u8,
cols: u8,
/// Already visited places in the dungeon.
visited_places: []std.DynamicBitSet,
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMap(p.Point, g.Entity),

pub fn init(arena: *std.heap.ArenaAllocator, rows: u8, cols: u8) !LevelMap {
    const alloc = arena.allocator();
    var visited_places = try alloc.alloc(std.DynamicBitSet, rows);
    for (0..rows) |r0| {
        visited_places[r0] = try std.DynamicBitSet.initEmpty(alloc, cols);
    }
    return .{
        .rows = rows,
        .cols = cols,
        .visited_places = visited_places,
        .remembered_objects = std.AutoHashMap(p.Point, g.Entity).init(alloc),
    };
}

pub fn format(
    self: LevelMap,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writer.print("LevelMap(", .{});
    for (0..self.rows) |r0| {
        try writer.writeByte('\n');
        for (0..self.cols) |c0| {
            if (self.remembered_objects.get(.{ .row = @intCast(r0 + 1), .col = @intCast(c0 + 1) })) |entity|
                try writer.print("{d}", .{entity})
            else if (self.visited_places[r0].isSet(c0))
                try writer.writeByte('#')
            else
                try writer.writeByte(' ');
        }
    }
    try writer.print("\n)", .{});
}

pub fn isVisited(self: LevelMap, place: p.Point) bool {
    if (place.row > self.rows or place.col > self.cols) return false;
    return self.visited_places[place.row - 1].isSet(place.col - 1);
}

pub fn addVisitedPlace(self: *LevelMap, visited_place: p.Point) !void {
    if (visited_place.row > self.rows or visited_place.col > self.cols) return;
    log.debug("Add visited place {any}\n{any}", .{ visited_place, self });
    self.visited_places[visited_place.row - 1].set(visited_place.col - 1);
}

pub fn rememberObject(self: *LevelMap, entity: g.Entity, place: p.Point) !void {
    log.debug("Remember object {any} at {any}\n{any}", .{ entity, place, self });
    self.remembered_objects.put(place, entity);
}

pub fn forgetObject(self: *LevelMap, place: p.Point) !void {
    log.debug("Forget object at {any}\n{any}", .{ place, self });
    _ = try self.remembered_objects.remove(place);
}
