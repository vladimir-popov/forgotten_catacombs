const std = @import("std");
const gm = @import("game");
const utf8 = @import("utf8");

pub fn drawWalls(alloc: std.mem.Allocator, buffer: *utf8.Buffer, walls: *const gm.Level.Walls) !void {
    var line = try alloc.alloc(u8,walls.cols);
    defer alloc.free(line);
    for (walls.bitsets.items) |row| {
        for (0..row.capacity()) |i| {
            line[i] = if (row.isSet(i)) '#' else ' ';
        }
        try buffer.addLine(line);
        @memset(line, 0);
    }
}

test "Draw walls" {
    // given:
    const alloc = std.testing.allocator;
    var buffer = utf8.Buffer.init(alloc);
    defer buffer.deinit();
    var walls = try gm.Level.Walls.initEmpty(alloc, 3, 5);
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
    try drawWalls(alloc, &buffer, &walls);

    // then:
    const actual = try buffer.toCString(alloc);
    defer alloc.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
