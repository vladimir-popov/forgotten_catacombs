const std = @import("std");
const game = @import("game");
const utf8 = @import("utf8");
const m = @import("math");

pub fn drawDungeon(
    alloc: std.mem.Allocator,
    buffer: *utf8.Buffer,
    dungeon: *const game.Dungeon,
    region: m.Region,
) !void {
    var line = try alloc.alloc(u8, region.cols);
    defer alloc.free(line);
    for (dungeon.walls.items) |row| {
        for (0..row.capacity()) |i| {
            line[i] = if (row.isSet(i)) '#' else ' ';
        }
        try buffer.addLine(line);
        @memset(line, 0);
    }
}

test drawDungeon {
    // given:
    const alloc = std.testing.allocator;
    var buffer = utf8.Buffer.init(alloc);
    defer buffer.deinit();
    var walls = try game.Dungeon.initEmpty(alloc, 3, 5);
    defer walls.deinit();
    walls.setWalls(1, 1, 5);
    walls.setWall(2, 1);
    walls.setWall(2, 5);
    walls.setWalls(3, 1, 5);

    const expected =
        \\#####
        \\#   #
        \\#####
    ;
    // when:
    try drawDungeon(alloc, &buffer, walls, .{ .r = 1, .c = 1, .rows = 3, .cols = 5 });

    // then:
    const actual = try buffer.toCString(alloc);
    defer alloc.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
