//! This is the level for tests
//!
//! ╔════════════════════════════════════════╗
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║••••••••••••••••••••••••••••••••••••••••║
//! ║════════════════════════════════════════║
const std = @import("std");
const g = @import("game");
const p = g.primitives;
const d = g.dungeon;

const Self = @This();

const dungeon_region: p.Region = p.Region{
    .top_left = .{ .row = 1, .col = 1 },
    .rows = g.DISPLAY_ROWS - 2,
    .cols = g.DISPLAY_COLS,
};

area: d.Area,

/// Uses arena to create a self instance and trying to generate a dungeon with passed seed.
pub fn generateDungeon(arena: *std.heap.ArenaAllocator) !d.Dungeon {
    const alloc = arena.allocator();
    const self = try alloc.create(Self);
    self.area = .init(dungeon_region);
    return try self.dungeon();
}

pub fn dungeon(self: *Self) !d.Dungeon {
    return .{
        .seed = 0,
        .type = .test_location,
        .parent = self,
        .rows = self.area.region.rows,
        .cols = self.area.region.cols,
        .entrance = .init(10, 23),
        .exit = .init(1, 23),
        .doorways = null,
        .vtable = .{
            .cellAtFn = cellAt,
            .placementWithFn = placementWith,
            .randomPlaceFn = randomPlace,
        },
    };
}

fn cellAt(_: *const anyopaque, _: p.Point) d.Dungeon.Cell {
    return .floor;
}

fn placementWith(ptr: *anyopaque, _: p.Point) ?d.Placement {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return .{ .area = &self.area };
}

fn randomPlace(_: *const anyopaque, rand: std.Random) p.Point {
    return .{
        .row = dungeon_region.top_left.row + rand.uintLessThan(u8, dungeon_region.rows - 2) + 1,
        .col = dungeon_region.top_left.col + rand.uintLessThan(u8, dungeon_region.cols - 2) + 1,
    };
}
