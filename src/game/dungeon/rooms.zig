const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const Dungeon = g.Dungeon;
const Room = g.Dungeon.Room;

/// Generate the room inside the passed region, and creates random interior inside the room.
/// Returns the actual region of the generated room
pub fn createRoom(dungeon: *g.Dungeon, _: std.Random, region: p.Region) !Room {
    return createEmptyRoom(dungeon, region);
}

fn createEmptyRoom(dungeon: *Dungeon, region: p.Region) Room {
    // generate walls:
    for (region.top_left.row..(region.top_left.row + region.rows)) |r| {
        if (r == region.top_left.row or r == region.bottomRightRow()) {
            dungeon.walls.setRowValue(@intCast(r), region.top_left.col, region.cols, true);
        } else {
            dungeon.walls.set(@intCast(r), @intCast(region.top_left.col));
            dungeon.walls.set(@intCast(r), @intCast(region.bottomRightCol()));
        }
    }
    // generate floor:
    dungeon.floor.setRegionValue(region, true);

    return region;
}

test "create empty room" {
    // given:
    const Rows = 12;
    const Cols = 12;
    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };

    var dungeon = try Dungeon.init(std.testing.allocator);
    defer dungeon.deinit();

    // when:
    const room = try createEmptyRoom(&dungeon, region);

    // then:
    try std.testing.expect(region.containsRegion(room));
    for (0..Rows) |r_idx| {
        const r: u8 = @intCast(r_idx + 1);
        for (0..Cols) |c_idx| {
            const c: u8 = @intCast(c_idx + 1);
            errdefer std.debug.print("r:{d} c:{d}\n", .{ r, c });

            const cell = dungeon.cellAt(.{ .row = r, .col = c });
            if (room.containsPoint(.{ .row = r, .col = c })) {
                const expect_wall =
                    (r == room.top_left.row or r == room.bottomRightRow() or
                    c == room.top_left.col or c == room.bottomRightCol());
                if (expect_wall) {
                    try std.testing.expectEqual(.wall, cell);
                } else {
                    try std.testing.expectEqual(.floor, cell);
                }
            } else {
                try std.testing.expectEqual(.nothing, cell);
            }
        }
    }
}
