const std = @import("std");
const bsp = @import("bsp.zig");

pub const Dungeon = @import("Dungeon.zig");

pub const Position = struct { row: u8, col: u8 };

pub const Health = struct { health: u8 };

pub const Sprite = struct { letter: []const u8 };

pub const Level = struct {
    dungeon: Dungeon,
    // items
    // enemies

    pub fn init(alloc: std.mem.Allocator, rand: std.Random) !Level {
        return .{ .dungeon = try Dungeon.bspGenerate(
            alloc,
            rand,
            Dungeon.ROWS,
            Dungeon.COLS,
        ) };
    }

    pub fn deinit(self: Level) void {
        self.dungeon.deinit();
    }
};

pub const Components = union(enum) {
    const Self = @This();

    position: Position,
    health: Health,
    sprite: Sprite,
    level: Level,

    pub fn deinit(self: Self) void {
        switch (self) {
            .level => self.level.deinit(),
            else => {},
        }
    }
};
