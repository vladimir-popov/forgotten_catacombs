const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const DungeonBuilder = @import("DungeonBuilder.zig");

const DungeonGenerator = @This();

context: *anyopaque,
generateFn: *const fn (ptr: *anyopaque, rand: std.Random, dungeon: DungeonBuilder) anyerror!void,

pub fn generateDungeon(
    self: DungeonGenerator,
    rand: std.Random,
    dungeon: DungeonBuilder,
) !void {
    try self.generateFn(self.context, rand, dungeon);
}
