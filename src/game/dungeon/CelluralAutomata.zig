const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

const log = std.log.scoped(.cellural_automata);

const CelluralAutomata = @This();

/// Chance for a given cell to be filled during intialization
P: u8,

pub fn generate(
    self: CelluralAutomata,
    comptime rows: u8,
    comptime cols: u8,
    bitmap: *p.BitMap(rows, cols),
    rand: std.Random,
) void {
    bitmap.clear();
    // Generate noise
    for (1..rows + 1) |r| {
        for (1..cols + 1) |c| {
            if (rand.intRangeLessThan(u8, 0, 100) < self.P) bitmap.set(r, c);
        }
    }
}

pub fn dumpToLog(
    comptime rows: u8,
    comptime cols: u8,
    bitmap: *const p.BitMap(rows, cols),
) void {
    var buf: [rows * (cols + 1)]u8 = undefined;
    var writer = std.io.fixedBufferStream(&buf);
    write(rows, cols, bitmap, writer.writer().any()) catch unreachable;
    log.debug("{s}", .{buf});
}

pub fn write(
    comptime rows: u8,
    comptime cols: u8,
    bitmap: *const p.BitMap(rows, cols),
    writer: std.io.AnyWriter,
) !void {
    for (1..rows + 1) |r| {
        for (1..cols + 1) |c| {
            try writer.writeByte(if (bitmap.isSet(r, c)) '#' else ' ');
        }
        try writer.writeByte('\n');
    }
}
