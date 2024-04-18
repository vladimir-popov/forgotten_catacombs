const std = @import("std");

pub const Position = struct { row: u8, col: u8 };

pub const Health = struct { health: u8 };

pub const Sprite = struct { letter: []const u8 };

pub const Level = struct {
    const Self = @This();

    rows: u8,
    cols: u8,
    walls: std.ArrayList(std.DynamicBitSet),

    pub fn init(alloc: std.mem.Allocator, rows: u8, cols: u8) !Self {
        var walls = try std.ArrayList(std.DynamicBitSet).initCapacity(alloc, rows);
        for (0..rows) |r| {
            var row = walls.addOneAssumeCapacity();
            row.* = try std.DynamicBitSet.initEmpty(alloc, cols);
            if (r == 0 or r == rows - 1) {
                row.setRangeValue(.{ .start = 0, .end = cols }, true);
            } else {
                row.set(0);
                row.set(cols - 1);
            }
        }
        return .{
            .rows = rows,
            .cols = cols,
            .walls = walls,
        };
    }

    pub fn deinit(self: Self) void {
        for (self.walls.items) |*row| {
            row.deinit();
        }
        self.walls.deinit();
    }

    pub fn hasWall(self: Self, position: Position) bool {
        if (position.row < 1 or position.row >= self.walls.items.len)
            return true;
        const row = self.walls.items[position.row - 1];
        if (position.col < 1 or position.col >= row.capacity())
            return true;
        return row.isSet(position.col - 1);
    }
};

pub const AllComponents = .{ Position, Health, Sprite, Level };
