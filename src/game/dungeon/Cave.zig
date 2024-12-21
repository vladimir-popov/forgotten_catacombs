const std = @import("std");
const g = @import("../game_pkg.zig");
const d = @import("dungeon_pkg.zig");
const p = g.primitives;

const Cave = @This();

pub const rows = g.DISPLAY_ROWS * 2;
pub const cols = g.DISPLAY_COLS * 2;

const whole_region: p.Region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols };

// The room of this cave with rocks inside
room: d.Room,
/// The bit mask of the places with floor and walls.
cells: p.BitMap(rows, cols),
entrance: ?p.Point = null,
exit: ?p.Point = null,

pub fn init(arena: *std.heap.ArenaAllocator) !Cave {
    return .{
        .cells = try p.BitMap(rows, cols).initEmpty(arena.allocator()),
        .room = d.Room.init(arena.allocator(), whole_region),
    };
}

pub fn dungeon(self: *Cave) d.Dungeon {
    return .{
        .parent = self,
        .rows = rows,
        .cols = cols,
        .entrance = self.entrance.?,
        .exit = self.exit.?,
        .vtable = .{
            .cellAtFn = cellAt,
            .placementWithFn = placementWith,
            .randomPlaceFn = randomPlace,
        },
    };
}

fn cellAt(ptr: *const anyopaque, place: p.Point) d.Dungeon.Cell {
    if (!whole_region.containsPoint(place)) return .nothing;

    const self: *const Cave = @ptrCast(@alignCast(ptr));

    return if (self.cells.isSet(place.row, place.col)) .rock else .floor;
}

fn placementWith(ptr: *anyopaque, place: p.Point) ?d.Placement {
    if (!whole_region.containsPoint(place)) return null;

    const self: *Cave = @ptrCast(@alignCast(ptr));
    return .{ .room = &self.room };
}

fn randomPlace(ptr: *const anyopaque, rand: std.Random) p.Point {
    const self: *const Cave = @ptrCast(@alignCast(ptr));
    return self.randomEmptyPlace(rand);
}

pub fn randomEmptyPlace(self: *const Cave, rand: std.Random) p.Point {
    while (true) {
        const row = whole_region.top_left.row + rand.uintLessThan(u8, whole_region.rows - 2) + 1;
        const col = whole_region.top_left.col + rand.uintLessThan(u8, whole_region.cols - 2) + 1;
        if (!self.cells.isSet(row, col)) return .{ .row = row, .col = col };
    }
}
