const std = @import("std");
const game = @import("game");
const utf8 = @import("utf8");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

pub fn drawDungeon(
    alloc: std.mem.Allocator,
    buffer: *utf8.Buffer,
    dungeon: *const game.Dungeon,
    region: p.Region,
) !void {
    var itr = dungeon.cellsInRegion(region) orelse return;
    var line = try alloc.alloc(u8, region.cols);
    defer alloc.free(line);

    while (itr.next()) |cell| {
        const idx = itr.current_place.col - itr.start_place.col;
        line[idx] = switch (cell) {
            .nothing => ' ',
            .floor => '.',
            .wall => '#',
            .opened_door => '\'',
            .closed_door => '+',
        };
        if (itr.current_place.col == itr.bottom_right_limit.col) {
            try buffer.addLine(line);
            @memset(line, 0);
        }
    }
}

test "draw walls" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var buffer = utf8.Buffer.init(std.testing.allocator);
    defer buffer.deinit();

    var dungeon = try game.Dungeon.initEmpty(arena.allocator());
    dungeon.walls.setRowValue(1, 1, 5, true);
    dungeon.walls.set(2, 1);
    dungeon.walls.set(2, 5);
    dungeon.walls.setRowValue(3, 1, 5, true);

    const expected =
        \\#####
        \\#   #
        \\#####
    ;
    // when:
    try drawDungeon(
        std.testing.allocator,
        &buffer,
        &dungeon,
        .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 },
    );

    // then:
    const actual = try buffer.toCString(std.testing.allocator);
    defer std.testing.allocator.free(actual);

    errdefer std.debug.print("Actual is:\n[{s}]\n", .{actual});
    try std.testing.expectEqualSlices(u8, expected, actual);
}
