//! Generic representation of the dungeon.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const d = @import("dungeon_pkg.zig");

const log = std.log.scoped(.dungeon);

/// Possible types of objects inside the dungeon.
pub const Cell = enum {
    nothing,
    floor,
    wall,
    door,
};

const Dungeon = @This();

pub const VTable = struct {
    /// Should return the cell of the dungeon on the passed place
    cellAtFn: *const fn (ptr: *const anyopaque, place: p.Point) Cell,
    /// Should return the placement that contains the passed place, or nothing,
    /// if the place is outside of all placements.
    placementWithFn: *const fn (ptr: *const anyopaque, place: p.Point) ?*const d.Placement,
    /// Should return random place inside random placement of the dungeon.
    randomPlaceFn: *const fn (ptr: *const anyopaque, rand: std.Random) p.Point,
};

/// The pointer to the original implementation of the dungeon.
parent: *const anyopaque,
/// The place with entrance to the level. Usually, it's the place with ladder to
/// an upper level.
entrance: p.Point,
/// The place with exit from the level. Usually, it's the place with ladder to
/// a bottom level.
exit: p.Point,
/// Index of all doorways by their place
doorways: *const std.AutoHashMap(p.Point, d.Doorway),
vtable: VTable,

pub inline fn cellAt(self: Dungeon, place: p.Point) Cell {
    return self.vtable.cellAtFn(self.parent, place);
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

        const cl = self.dungeon.cellAt(self.current_place);
        self.next_place = self.current_place.movedTo(.right);
        if (self.next_place.col > self.region.bottomRightCol()) {
            self.next_place.col = self.region.top_left.col;
            self.next_place.row += 1;
        }
        return cl;
    }
};

pub fn cellsInRegion(self: *const Dungeon, region: p.Region) CellsIterator {
    return .{
        .dungeon = self,
        .region = region,
        .next_place = region.top_left,
    };
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

pub inline fn doorwayAt(self: Dungeon, place: p.Point) ?d.Doorway {
    return self.doorways.get(place);
}

pub fn placementWith(self: Dungeon, place: p.Point) ?*const d.Placement {
    return self.vtable.placementWithFn(self.parent, place);
}

pub fn randomPlace(self: Dungeon, rand: std.Random) p.Point {
    return self.vtable.randomPlaceFn(self.parent, rand);
}

pub fn dumpToLog(self: Dungeon) void {
    if (std.log.logEnabled(.debug, .dungeon)) {
        var buf: [(g.DUNGEON_ROWS + 1) * g.DUNGEON_COLS]u8 = undefined;
        var writer = std.io.fixedBufferStream(&buf);
        self.write(writer.writer().any()) catch unreachable;
        log.debug("{s}", .{buf});
    }
}

pub fn write(
    self: Dungeon,
    writer: std.io.AnyWriter,
) !void {
    var itr = self.cellsInRegion(g.DUNGEON_REGION);
    var row: usize = 1;
    var col: usize = 1;
    while (itr.next()) |cell| {
        if (col > g.DUNGEON_COLS) {
            col = 1;
            try writer.writeByte('\n');
        }
        const symbol: u8 = switch (cell) {
            .wall => '#',
            .floor => '.',
            .door => '\'',
            else => ' ',
        };
        try writer.writeByte(symbol);
        row += 1;
        col += 1;
    }
}
