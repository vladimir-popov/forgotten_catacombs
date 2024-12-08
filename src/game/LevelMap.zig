const std = @import("std");
const g = @import("game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.level_map);

const LevelMap = @This();

rows: u8,
cols: u8,
/// Already visited places in the dungeon.
/// It has only floor cells
visited_places: []std.DynamicBitSet,
/// Index over visited placements.
/// Used to speed up adding already visited placement
visited_placements: std.AutoHashMap(*const d.Placement, void),
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
        .visited_placements = std.AutoHashMap(*const d.Placement, void).init(alloc),
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
    try self.visited_places[visited_place.row - 1].set(visited_place.col - 1);
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
    self.setVisitedRegion(room.region, true);
    for (room.inner_rooms.items) |ir| {
        self.setVisitedRegion(ir.innerRegion(), false);
    }
}

fn setVisitedRegion(self: *LevelMap, region: p.Region, value: bool) void {
    const to_row = @min(self.rows, region.bottomRightRow());
    const to_col = @min(self.cols, region.bottomRightCol());
    for (region.top_left.row - 1..to_row) |r0| {
        self.visited_places[r0].setRangeValue(
            .{ .start = region.top_left.col - 1, .end = to_col },
            value,
        );
    }
}

inline fn setVisitedRowValue(self: *LevelMap, row: u8, from_col: u8, count: u8, value: bool) void {
    self.visited_places[row - 1].setRangeValue(
        .{ .start = from_col - 1, .end = from_col + count - 1 },
        value,
    );
}

inline fn setVisitedAt(self: *LevelMap, place: p.Point) void {
    self.visited_places[place.row - 1].set(place.col - 1);
}

fn addVisitedPassage(self: *LevelMap, passage: d.Passage) void {
    var prev = passage.turns.items[0];
    for (passage.turns.items[1..]) |curr| {
        self.setVisitedAt(curr.corner(prev.to_direction));
        if (prev.to_direction.isHorizontal()) {
            self.setVisitedRowValue(
                prev.place.row,
                @min(prev.place.col, curr.place.col),
                distance(prev.place.col, curr.place.col),
                true,
            );
            if (prev.place.row > 1)
                self.setVisitedRowValue(
                    prev.place.row - 1,
                    @min(prev.place.col, curr.place.col),
                    distance(prev.place.col, curr.place.col),
                    true,
                );
            if (prev.place.row < self.rows - 1)
                self.setVisitedRowValue(
                    prev.place.row + 1,
                    @min(prev.place.col, curr.place.col),
                    distance(prev.place.col, curr.place.col),
                    true,
                );
        } else {
            for (@min(prev.place.row, curr.place.row) - 1..@max(prev.place.row, curr.place.row)) |r0| {
                self.visited_places[r0].set(prev.place.col - 1);
                if (prev.place.col > 1)
                    self.visited_places[r0].set(prev.place.col - 2);
                if (prev.place.col < self.cols - 1)
                    self.visited_places[r0].set(prev.place.col);
            }
        }
        prev = curr;
    }
}

inline fn distance(x: u8, y: u8) u8 {
    return @max(x, y) - @min(x, y) + 1;
}
