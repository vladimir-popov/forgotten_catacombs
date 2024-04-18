const std = @import("std");
const gm = @import("game");
const utf8 = @import("utf8");

pub fn drawLevel(alloc: std.mem.Allocator, buffer: *utf8.Buffer, level: *const gm.Level) !void {
    var line = try alloc.alloc(u8, level.cols);
    defer alloc.free(line);
    for (level.walls.items) |row| {
        for (0..row.capacity()) |i| {
            line[i] = if (row.isSet(i)) '#' else ' ';
        }
        try buffer.addLine(line);
        @memset(line, 0);
    }
}

test "Draw level" {
    // given:
    const alloc = std.testing.allocator;
    var buffer = utf8.Buffer.init(alloc);
    defer buffer.deinit();
    const level = try gm.Level.init(alloc, 3, 5);
    defer level.deinit();
    const expected =
        \\#####
        \\#   #
        \\#####
    ;
    // when:
    try drawLevel(alloc, &buffer, &level);

    // then:
    const actual = try buffer.toCString(alloc);
    defer alloc.free(actual);
    try std.testing.expectEqualSlices(u8, expected, actual);
}
