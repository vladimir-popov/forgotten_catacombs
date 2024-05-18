const std = @import("std");
const dung = @import("Dungeon.zig");

// Playdate resolution: h:240 × w:400 pixels
// we expect at least 4x4 sprite to render the whole level map
pub const ROWS: u8 = 40;
pub const COLS: u8 = 100;

pub const Dungeon = dung.Dungeon(ROWS, COLS);

pub const Position = struct {
    row: u8,
    col: u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    health: u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Sprite = struct {
    letter: []const u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Level = struct {
    dungeon: Dungeon,
    // items
    // enemies

    pub fn init(alloc: std.mem.Allocator, rand: std.Random) !Level {
        return .{ .dungeon = try Dungeon.bspGenerate(
            alloc,
            rand,
        ) };
    }

    pub fn deinit(self: *Level) void {
        self.dungeon.deinit();
    }
};

pub const Components = union {
    position: Position,
    health: Health,
    sprite: Sprite,
    level: Level,
};
