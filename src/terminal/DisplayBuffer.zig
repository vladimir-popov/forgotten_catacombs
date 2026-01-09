const std = @import("std");
const tty = @import("tty.zig");
const g = @import("game");

pub const DisplayCell = struct {
    symbol: u21,
    mode: g.DrawingMode,
};

/// ROWS and COLS - the size of the buffer included the border.
pub fn DisplayBuffer(comptime ROWS: u8, comptime COLS: u8) type {
    return struct {
        const Self = @This();

        pub const DisplayLine = [COLS]DisplayCell;

        alloc: std.mem.Allocator,
        lines: []DisplayLine,
        rows: u8 = ROWS,
        cols: u8 = COLS,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{ .alloc = alloc, .lines = try alloc.alloc(DisplayLine, ROWS) };
        }

        pub fn deinit(self: Self) void {
            self.alloc.free(self.lines);
        }

        /// Replaces all cells of the buffer by the border and spaces
        pub fn cleanAndWrap(self: Self) void {
            self.setUtf8Text("╔" ++ "═" ** (COLS - 2) ++ "╗", 0, 0, .normal);
            self.setUtf8Text("╚" ++ "═" ** (COLS - 2) ++ "╝", ROWS - 1, 0, .normal);
            for (1..(ROWS - 1)) |r| {
                self.setUtf8Text("║" ++ " " ** (COLS - 2) ++ "║", @intCast(r), 0, .normal);
            }
        }

        pub inline fn setSymbol(
            self: Self,
            symbol: u21,
            row_idx: usize,
            col_idx: usize,
            mode: g.DrawingMode,
        ) void {
            self.lines[row_idx][col_idx] = .{ .symbol = symbol, .mode = mode };
        }

        pub fn setAsciiText(
            self: Self,
            text: []const u8,
            row_idx: usize,
            col_idx: usize,
            mode: g.DrawingMode,
        ) void {
            for (text, 0..) |s, i| {
                self.lines[row_idx][col_idx + i] = .{ .symbol = s, .mode = mode };
            }
        }

        pub fn setUtf8Text(
            self: Self,
            comptime text: []const u8,
            row_idx: usize,
            col_idx: usize,
            mode: g.DrawingMode,
        ) void {
            const view = std.unicode.Utf8View.initComptime(text);
            var itr = view.iterator();
            var i = col_idx;
            while (itr.nextCodepoint()) |u| {
                self.lines[row_idx][i] = .{ .symbol = u, .mode = mode };
                i += 1;
            }
        }

        /// Flashes the buffer to the `writer`.
        pub fn writeBuffer(self: Self, writer: *std.Io.Writer, rows_pad: u8, cols_pad: u8) !void {
            var buf: [4]u8 = undefined;
            for (self.lines, rows_pad..) |line, i| {
                var mode: g.DrawingMode = .normal;
                try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
                for (line) |cell| {
                    if (mode != cell.mode) {
                        mode = cell.mode;
                        switch (mode) {
                            .inverted => _ = try writer.write(tty.Text.SGR_INVERT_COLORS),
                            else => _ = try writer.write(tty.Text.SGR_RESET),
                        }
                    }
                    if (cell.symbol == 0) {
                        try writer.writeByte(' ');
                    } else if (cell.symbol <= 127) {
                        try writer.writeByte(@truncate(cell.symbol));
                    } else {
                        const len = try std.unicode.utf8Encode(cell.symbol, &buf);
                        _ = try writer.write(buf[0..len]);
                    }
                }
                _ = try writer.write(tty.Text.SGR_RESET);
            }
        }
    };
}
