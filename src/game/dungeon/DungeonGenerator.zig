const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const DungeonGenerator = @This();

context: *anyopaque,
generateFn: *const fn (ptr: *anyopaque, rand: std.Random, dungeon: *g.Dungeon) anyerror!void,

pub fn generateDungeon(
    self: DungeonGenerator,
    rand: std.Random,
    dungeon: *g.Dungeon,
) !void {
    try self.generateFn(self.context, rand, dungeon);
}
