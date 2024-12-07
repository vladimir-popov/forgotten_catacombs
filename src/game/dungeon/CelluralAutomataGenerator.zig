const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.cellural_automata_generator);

const CelluralAutomataGenerator = @This();

/// Chance for a given cell to be filled during initialization
init_walls_percent: u8 = 45,
/// Max count of generations
generations_count: u8 = 6,
/// The minimal count of walls around the wall to keep the state
min_walls_to_keep_wall: u8 = 5,
max_floors_to_create_wall: u8 = 2,

pub fn generateDungeon(
    self: CelluralAutomataGenerator,
    arena: *std.heap.ArenaAllocator,
    rand: std.Random,
) !d.Dungeon {
    const alloc = arena.allocator();

    const generate_arena = try alloc.create(std.heap.ArenaAllocator);
    defer alloc.destroy(generate_arena);

    generate_arena.* = std.heap.ArenaAllocator.init(alloc);
    defer generate_arena.deinit();

    const dungeon = try arena.allocator().create(d.OneRoomDungeon);
    dungeon.* = try d.OneRoomDungeon.init(arena);
    dungeon.cells.copyFrom(try self.generate(d.OneRoomDungeon.rows, d.OneRoomDungeon.cols, generate_arena, rand));
    dungeon.entrance = dungeon.randomEmptyPlace(rand);
    dungeon.exit = dungeon.randomEmptyPlace(rand);
    return dungeon.dungeon();
}

pub fn generate(
    self: CelluralAutomataGenerator,
    comptime rows: u8,
    comptime cols: u8,
    arena: *std.heap.ArenaAllocator,
    rand: std.Random,
) !*p.BitMap(rows, cols) {
    var bitmaps = [_]*p.BitMap(rows, cols){
        try arena.allocator().create(p.BitMap(rows, cols)),
        try arena.allocator().create(p.BitMap(rows, cols)),
    };
    bitmaps[0].* = try p.BitMap(rows, cols).initEmpty(arena.allocator());
    bitmaps[1].* = try p.BitMap(rows, cols).initFull(arena.allocator());
    var i: u1 = 0;
    // Generate noise and border for the first generation
    for (0..rows) |r0| {
        for (0..cols) |c0| {
            if (r0 == 0 or c0 == 0 or r0 == rows - 1 or c0 == cols - 1) {
                bitmaps[i].set0(r0, c0);
                continue;
            }
            if (rand.intRangeLessThan(u8, 0, 100) < self.init_walls_percent) {
                bitmaps[i].set0(r0, c0);
            }
        }
    }
    for (0..self.generations_count) |gen| {
        for (0..rows) |r0| {
            for (0..cols) |c0| {
                const ns = neighbors(bitmaps[i], r0, c0);
                if (ns[0] >= self.min_walls_to_keep_wall or ns[1] <= self.max_floors_to_create_wall)
                    bitmaps[i +% 1].set0(r0, c0)
                else
                    bitmaps[i +% 1].unset0(r0, c0);
            }
        }
        if (std.log.logEnabled(.debug, .cellural_automata_generator)) {
            log.debug("Generation {d}", .{gen});
            try dumpToLog(rows, cols, bitmaps[i]);
        }
        i +%= 1;
    }
    return bitmaps[i -% 1];
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

pub fn dumpToLog(
    comptime rows: usize,
    comptime cols: usize,
    bitmap: *const p.BitMap(rows, cols),
) !void {
    var buf: [rows * (cols + 1)]u8 = undefined;
    var writer = std.io.fixedBufferStream(&buf);
    try write(rows, cols, bitmap, writer.writer().any());
    log.debug("-------------\n{s}------------", .{buf});
}

pub fn write(
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
