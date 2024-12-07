const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.cellural_automata);

const CelluralAutomata = @This();

/// This arena is used to create generations on generating bitmap.
/// Note, this arena will be clean up at the beginning of the `generate` method.
arena: *std.heap.ArenaAllocator,
/// Chance for a given cell to be filled during initialization
init_walls_percent: u8 = 45,
/// Max count of generations
generations_count: u8 = 6,
/// The minimal count of walls around the wall to keep the state
min_walls_to_keep_wall: u8 = 5,
max_floors_to_create_wall: u8 = 2,

/// Generates a bitmap according to the algorithm described here:
/// https://www.roguebasin.com/index.php?title=Cellular_Automata_Method_for_Generating_Random_Cave-Like_Levels
///
/// Note, the this method is used arena allocator, and reset it at the beginning.
/// You should not use result of this method directly, and should copy it
/// instead.
pub fn generate(
    self: CelluralAutomata,
    comptime rows: u8,
    comptime cols: u8,
    rand: std.Random,
) !*p.BitMap(rows, cols) {
    _ = self.arena.reset(.retain_capacity);
    var generations = [_]*p.BitMap(rows, cols){
        try self.arena.allocator().create(p.BitMap(rows, cols)),
        try self.arena.allocator().create(p.BitMap(rows, cols)),
    };
    generations[0].* = try p.BitMap(rows, cols).initEmpty(self.arena.allocator());
    generations[1].* = try p.BitMap(rows, cols).initFull(self.arena.allocator());
    var i: u1 = 0;
    // Generate noise and border for the first generation
    for (0..rows) |r0| {
        for (0..cols) |c0| {
            if (r0 == 0 or c0 == 0 or r0 == rows - 1 or c0 == cols - 1) {
                generations[i].set0(r0, c0);
                continue;
            }
            if (rand.intRangeLessThan(u8, 0, 100) < self.init_walls_percent) {
                generations[i].set0(r0, c0);
            }
        }
    }
    for (0..self.generations_count) |gen| {
        for (0..rows) |r0| {
            for (0..cols) |c0| {
                const ns = neighbors(generations[i], r0, c0);
                if (ns[0] >= self.min_walls_to_keep_wall or ns[1] <= self.max_floors_to_create_wall)
                    generations[i +% 1].set0(r0, c0)
                else
                    generations[i +% 1].unset0(r0, c0);
            }
        }
        if (std.log.logEnabled(.debug, .cellural_automata_generator)) {
            log.debug("Generation {d}", .{gen});
            try dumpToLog(rows, cols, generations[i]);
        }
        i +%= 1;
    }
    return generations[i -% 1];
}

/// Returns numbers of neighbors for the cell. The first number is count of
/// the walls near the cell in step 1, the second number is count of the walls
/// in step 2. Both numbers include the cell itself.
fn neighbors(bitmap: anytype, row_idx: usize, col_idx: usize) [2]u8 {
    var counts: [2]u8 = [2]u8{ 9, 25 };
    for (row_idx -| 2..row_idx + 3) |r0| {
        for (col_idx -| 2..col_idx + 3) |c0| {
            if (bitmap.isOutside0(r0, c0)) continue;

            if (!bitmap.isSet0(r0, c0)) {
                counts[1] -= 1;
                if (p.diff(usize, r0, row_idx) < 2 and p.diff(usize, c0, col_idx) < 2)
                    counts[0] -= 1;
            }
        }
    }
    return counts;
}

fn dumpToLog(
    comptime rows: usize,
    comptime cols: usize,
    bitmap: *const p.BitMap(rows, cols),
) !void {
    var buf: [rows * (cols + 1)]u8 = undefined;
    var writer = std.io.fixedBufferStream(&buf);
    try write(rows, cols, bitmap, writer.writer().any());
    log.debug("\n{s}", .{buf});
}

fn write(
    comptime rows: u8,
    comptime cols: u8,
    bitmap: *const p.BitMap(rows, cols),
    writer: std.io.AnyWriter,
) !void {
    for (1..rows + 1) |r| {
        for (1..cols + 1) |c| {
            try writer.writeByte(if (bitmap.isSet(@intCast(r), @intCast(c))) '#' else ' ');
        }
        try writer.writeByte('\n');
    }
}
