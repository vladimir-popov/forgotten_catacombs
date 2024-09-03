const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

const Dungeon = g.Dungeon;
const Room = g.Dungeon.Room;

pub fn createEmptyRoom(dungeon: *Dungeon, region: p.Region) !Room {
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
    var floor = region;
    floor.top_left.row += 1;
    floor.top_left.col += 1;
    floor.rows -= 2;
    floor.cols -= 2;
    dungeon.floor.setRegionValue(floor, true);

    return region;
}
