const std = @import("std");
const game = @import("game");
const utf8 = @import("utf8");
const p = game.primitives;

pub fn drawDungeon(
    alloc: std.mem.Allocator,
    buffer: *utf8.Buffer,
    dungeon: *const game.Dungeon,
    region: p.Region,
) !void {
    var line = try alloc.alloc(u8, region.cols);
    defer alloc.free(line);
    var itr = dungeon.cells();
    while (itr.next()) |cell| {
        line[itr.current_place.col - 1] = switch (cell) {
            .floor => ' ',
            .wall => '#',
            .opened_door => '\'',
            .closed_door => '+',
        };
        if (itr.current_place.col == dungeon.cols) {
            try buffer.addLine(line);
            @memset(line, 0);
        }
    }
}

test "draw walls" {
    // given:
    const alloc = std.testing.allocator;
    var buffer = utf8.Buffer.init(alloc);
    defer buffer.deinit();
    var dungeon = try game.Dungeon.init(alloc, 3, 5);
    defer dungeon.deinit();
    dungeon.walls.setRowOfWalls(1, 1, 5);
    dungeon.walls.setWall(2, 1);
    dungeon.walls.setWall(2, 5);
    dungeon.walls.setRowOfWalls(3, 1, 5);

    const expected =
        \\#####
        \\#   #
        \\#####
    ;
    // when:
    try drawDungeon(alloc, &buffer, &dungeon, .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 });

    // then:
    const actual = try buffer.toCString(alloc);
    defer alloc.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
