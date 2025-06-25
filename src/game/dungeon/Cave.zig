const std = @import("std");
const g = @import("../game_pkg.zig");
const d = @import("dungeon_pkg.zig");
const p = g.primitives;

pub fn Cave(comptime rows: u8, cols: u8) type {
    return struct {
        const Self = @This();

        // The room of this cave with rocks inside
        room: d.Room,
        /// The bit mask of the places with floor and walls.
        cells: p.BitMap(rows, cols),
        entrance: ?p.Point = null,
        exit: ?p.Point = null,

        pub fn init(arena: *std.heap.ArenaAllocator) !Self {
            return .{
                .room = d.Room.init(
                    arena,
                    p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols },
                ),
                .cells = try p.BitMap(rows, cols).initEmpty(arena.allocator()),
            };
        }

        pub fn dungeon(self: *Self, seed: u64) d.Dungeon {
            return .{
                .seed = seed,
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
            const self: *const Self = @ptrCast(@alignCast(ptr));

            if (!self.room.region.containsPoint(place)) return .nothing;

            return if (self.cells.isSet(place.row, place.col)) .rock else .floor;
        }

        fn placementWith(ptr: *anyopaque, place: p.Point) ?d.Placement {
            const self: *Self = @ptrCast(@alignCast(ptr));
            if (!self.room.region.containsPoint(place)) return null;

            return .{ .room = &self.room };
        }

        fn randomPlace(ptr: *const anyopaque, rand: std.Random) p.Point {
            const self: *const Self = @ptrCast(@alignCast(ptr));
            return self.randomEmptyPlace(rand);
        }

        pub fn randomEmptyPlace(self: *const Self, rand: std.Random) p.Point {
            while (true) {
                const row = self.room.region.top_left.row + rand.uintLessThan(u8, self.room.region.rows - 2) + 1;
                const col = self.room.region.top_left.col + rand.uintLessThan(u8, self.room.region.cols - 2) + 1;
                if (!self.cells.isSet(row, col)) return .{ .row = row, .col = col };
            }
        }
    };
}
