const std = @import("std");
const g = @import("game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.level_map);

const LevelMap = @This();

/// Already visited places in the dungeon.
/// It has only floor cells
visited_places: p.BitMap(g.DUNGEON_ROWS, g.DUNGEON_COLS),
/// Index over visited placements.
/// Used to speed up adding already visited placement
visited_placements: std.AutoHashMap(*const d.Placement, void),
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMap(p.Point, g.Entity),

pub fn init(alloc: std.mem.Allocator) !LevelMap {
    return .{
        .visited_places = try p.BitMap(g.DUNGEON_ROWS, g.DUNGEON_COLS).initEmpty(alloc),
        .visited_placements = std.AutoHashMap(*const d.Placement, void).init(alloc),
        .remembered_objects = std.AutoHashMap(p.Point, g.Entity).init(alloc),
    };
}

pub fn deinit(self: *LevelMap) void {
    self.visited_places.deinit();
    self.visited_placements.deinit();
    self.remembered_objects.deinit();
}

pub fn clearRetainingCapacity(self: *LevelMap) void {
    self.visited_places.clear();
    self.visited_placements.clearRetainingCapacity();
    self.remembered_objects.clearRetainingCapacity();
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
    for (1..g.DUNGEON_ROWS + 1) |r| {
        try writer.writeByte('\n');
        for (1..g.DUNGEON_COLS + 1) |c| {
            if (self.remembered_objects.get(.{ .row = @intCast(r), .col = @intCast(c) })) |entity|
                try writer.print("{d}", .{entity})
            else if (self.visited_places.isSet(@intCast(r), @intCast(c)))
                try writer.writeByte('#')
            else
                try writer.writeByte(' ');
        }
    }
    try writer.print("\n)", .{});
}

pub fn addVisitedPlace(self: *LevelMap, visited_place: p.Point) !void {
    try self.visited_places.set(visited_place.row, visited_place.col);
    log.debug("Added visited place {any}\n{any}", .{ visited_place, self });
}

pub fn rememberObject(self: *LevelMap, entity: g.Entity, place: p.Point) !void {
    self.remembered_objects.put(place, entity);
    log.debug("Remembered object {any} at {any}\n{any}", .{ entity, place, self });
}

pub fn forgetObject(self: *LevelMap, place: p.Point) !void {
    _ = try self.remembered_objects.remove(place);
    log.debug("Forgotten object at {any}\n{any}", .{ place, self });
}

pub fn addVisitedPlacement(self: *LevelMap, placement: *const d.Placement) !void {
    if (self.visited_placements.contains(placement)) return;

    switch (placement.*) {
        .room => |room| self.addVisitedRoom(room),
        .passage => |ps| self.addVisitedPassage(ps),
    }
    log.debug("Added visited placement {any}\n{any}", .{ placement, self });
}

fn addVisitedRoom(self: *LevelMap, room: d.Room) void {
    self.visited_places.setRegionValue(room.region, true);
    for (room.inner_rooms.items) |ir| {
        self.visited_places.setRegionValue(ir.innerRegion(), false);
    }
}

fn addVisitedPassage(self: *LevelMap, passage: d.Passage) void {
    var prev = passage.turns.items[0];
    for (passage.turns.items[1..]) |curr| {
        self.visited_places.setAt(curr.corner(prev.to_direction));
        if (prev.to_direction.isHorizontal()) {
            self.visited_places.setRowValue(
                prev.place.row,
                @min(prev.place.col, curr.place.col),
                distance(prev.place.col, curr.place.col),
                true,
            );
            if (prev.place.row > 1)
                self.visited_places.setRowValue(
                    prev.place.row - 1,
                    @min(prev.place.col, curr.place.col),
                    distance(prev.place.col, curr.place.col),
                    true,
                );
            if (prev.place.row < g.DUNGEON_ROWS - 1)
                self.visited_places.setRowValue(
                    prev.place.row + 1,
                    @min(prev.place.col, curr.place.col),
                    distance(prev.place.col, curr.place.col),
                    true,
                );
        } else {
            for (@min(prev.place.row, curr.place.row)..@max(prev.place.row, curr.place.row) + 1) |r| {
                self.visited_places.set(@intCast(r), prev.place.col);
                if (prev.place.col > 1)
                    self.visited_places.set(@intCast(r), prev.place.col - 1);
                if (prev.place.col < g.DUNGEON_COLS - 1)
                    self.visited_places.set(@intCast(r), prev.place.col + 1);
            }
        }
        prev = curr;
    }
}

inline fn distance(x: u8, y: u8) u8 {
    return @max(x, y) - @min(x, y) + 1;
}
