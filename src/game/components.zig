const std = @import("std");
const bsp = @import("bsp.zig");

pub const Position = struct { row: u8, col: u8 };

pub const Health = struct { health: u8 };

pub const Sprite = struct { letter: []const u8 };

pub const Level = struct {
    pub const Walls = struct {
        rows: u8,
        cols: u8,
        bitsets: std.ArrayList(std.DynamicBitSet),

        pub fn initEmpty(alloc: std.mem.Allocator, rows: u8, cols: u8) !Walls {
            var bitsets = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
            for (0..rows) |_| {
                const row = bitsets.addOneAssumeCapacity();
                row.* = try std.DynamicBitSet.initEmpty(alloc, cols);
            }
            return .{
                .rows = rows,
                .cols = cols,
                .bitsets = bitsets,
            };
        }

        pub fn deinit(self: Walls) void {
            for (self.bitsets.items) |*row| {
                row.deinit();
            }
            self.bitsets.deinit();
        }

        pub fn hasWall(self: Walls, position: Position) bool {
            if (position.row < 1 or position.row >= self.bitsets.items.len)
                return true;
            const row = self.bitsets.items[position.row - 1];
            if (position.col < 1 or position.col >= row.capacity())
                return true;
            return row.isSet(position.col - 1);
        }

        pub fn setWall(self: *Walls, row: u8, col: u8) void {
            self.bitsets.items[row - 1].set(col - 1);
        }

        pub fn setWalls(self: *Walls, row: u8, from_co: u8, count: u8) void {
            self.bitsets.items[row - 1].setRangeValue(.{ .start = from_co - 1, .end = from_co + count - 1 }, true);
        }
    };

    walls: Walls,

    pub fn init(alloc: std.mem.Allocator, rand: std.Random, rows: u8, cols: u8) !Level {
        return .{ .walls = try bsp.generateMap(alloc, rand, rows, cols, 10, 10) };
    }

    pub fn deinit(self: Level) void {
        self.walls.deinit();
    }
};

pub const AllComponents = .{ Position, Health, Sprite, Level };
