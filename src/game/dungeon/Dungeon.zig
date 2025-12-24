//! Generic representation of the dungeon.
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const d = @import("dungeon_pkg.zig");

const log = std.log.scoped(.dungeon);

pub const Type = enum {
    test_location,
    first_location,
    cave,
    catacomb,
};

/// Possible types of objects inside the dungeon.
/// This is not part of ecs, but the part of the landscape.
pub const Cell = enum(u6) {
    // ' '
    nothing,
    // │┐┌─┘└├┤┬┴┼
    @"│" = 1,
    @"┐",
    @"┌",
    @"─",
    @"┘",
    @"└",
    @"├",
    @"┤",
    @"┬",
    @"┴",
    @"┼",
    // '.'
    floor,
    // '''
    doorway,
    // '▒'
    wall,
    // '#'
    rock,
    // '~'
    water,
};

const Dungeon = @This();

pub const VTable = struct {
    /// Should return the cell of the dungeon on the passed place
    cellAtFn: *const fn (parent: *const anyopaque, place: p.Point) Cell,
    /// Should return the placement that contains the passed place, or nothing,
    /// if the place is outside of all placements.
    placementWithFn: *const fn (parent: *anyopaque, place: p.Point) ?d.Placement,
    /// Should return random place to put an enemy.
    randomPlaceFn: *const fn (parent: *const anyopaque, rand: std.Random) p.Point,
};

/// The seed that was used to generate this dungeon
seed: u64,
type: Type,
/// The pointer to the original implementation of the dungeon.
parent: *anyopaque,
rows: u8,
cols: u8,
/// The place with entrance to the level. Usually, it's the place with ladder to
/// an upper level.
entrance: p.Point,
/// The place with exit from the level. Usually, it's the place with ladder to
/// a bottom level.
exit: p.Point,
/// Index of all doorways by their place
doorways: ?*const std.AutoHashMapUnmanaged(p.Point, d.Doorway) = null,
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

pub inline fn doorwayAt(self: Dungeon, place: p.Point) ?*d.Doorway {
    if (self.doorways) |dws|
        return dws.getPtr(place)
    else
        return null;
}

pub fn placementWith(self: Dungeon, place: p.Point) ?d.Placement {
    return self.vtable.placementWithFn(self.parent, place);
}

pub fn randomPlace(self: Dungeon, rand: std.Random) p.Point {
    return self.vtable.randomPlaceFn(self.parent, rand);
}

pub fn dumpToLog(self: Dungeon) void {
    var buf: [(g.DUNGEON_COLS + 1) * g.DUNGEON_ROWS]u8 = undefined;
    const real_size: usize = @as(usize, @intCast(self.rows)) * (self.cols + 1);
    var writer = std.Io.fixedBufferStream(&buf);
    _ = self.write(writer.writer().any()) catch unreachable;
    log.debug("Dungeon:\n{s}", .{buf[0..real_size]});
}

pub fn write(
    self: Dungeon,
    writer: *std.Io.Writer,
) !usize {
    var itr = self.cellsInRegion(.{ .top_left = .{ .row = 1, .col = 1 }, .rows = self.rows, .cols = self.cols });
    var row: usize = 1;
    var col: usize = 1;
    var len: usize = 0;
    while (itr.next()) |cell| {
        if (col > self.cols) {
            col = 1;
            try writer.writeByte('\n');
            len += 1;
        }
        const symbol: u8 = switch (cell) {
            .nothing => ' ',
            .floor => '.',
            .doorway => '\'',
            else => '#',
        };
        try writer.writeByte(symbol);
        len += 1;
        row += 1;
        col += 1;
    }
    return len;
}
