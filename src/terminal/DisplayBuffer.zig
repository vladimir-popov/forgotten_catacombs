const std = @import("std");
const tty = @import("tty.zig");
const g = @import("game");

pub const DisplayCell = struct {
    symbol: union(enum) { ascii: u8, utf8: u21 },
    mode: g.Runtime.DrawingMode,
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

        pub fn clean(self: Self) void {
            self.setUtf8Text("╔" ++ "═" ** (COLS - 2) ++ "╗", 0, 0, .normal);
            self.setUtf8Text("╚" ++ "═" ** (COLS - 2) ++ "╝", ROWS - 1, 0, .normal);
            for (1..(ROWS - 1)) |r| {
                self.setUtf8Text("║" ++ " " ** (COLS - 2) ++ "║", @intCast(r), 0, .normal);
            }
        }

        pub fn setAsciiSymbol(
            self: Self,
            symbol: u8,
            row: u8,
            col: u8,
            mode: g.Render.DrawingMode,
        ) void {
            self.lines[row][col] = .{ .symbol = .{ .ascii = symbol }, .mode = mode };
        }

        pub fn setUtf8Symbol(
            self: Self,
            symbol: u21,
            row: u8,
            col: u8,
            mode: g.Runtime.DrawingMode,
        ) void {
            self.lines[row][col] = .{ .symbol = .{ .utf8 = symbol }, .mode = mode };
        }

        pub fn setAsciiText(
            self: Self,
            text: []const u8,
            row: u8,
            col: u8,
            mode: g.Runtime.DrawingMode,
        ) void {
            for (text, 0..) |s, i| {
                self.lines[row][col + i] = .{ .symbol = .{ .ascii = s }, .mode = mode };
            }
        }

        pub fn setUtf8Text(
            self: Self,
            comptime text: []const u8,
            row: u8,
            col: u8,
            mode: g.Runtime.DrawingMode,
        ) void {
            const view = std.unicode.Utf8View.initComptime(text);
            var itr = view.iterator();
            var i = col;
            while (itr.nextCodepoint()) |u| {
                self.lines[row][i] = .{ .symbol = .{ .utf8 = u }, .mode = mode };
                i += 1;
            }
        }

        pub fn writeBuffer(self: Self, writer: std.io.AnyWriter, rows_pad: u8, cols_pad: u8) !void {
            var buf: [4]u8 = undefined;
            for (self.lines, rows_pad..) |line, i| {
                var mode: g.Runtime.DrawingMode = .normal;
                try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
                for (line) |symbol| {
                    if (mode != symbol.mode) {
                        mode = symbol.mode;
                        switch (mode) {
                            .inverted => _ = try writer.write(tty.Text.SGR_INVERT_COLORS),
                            else => _ = try writer.write(tty.Text.SGR_RESET),
                        }
                    }
                    switch (symbol.symbol) {
                        .ascii => |b| try writer.writeByte(b),
                        .utf8 => |u| {
                            const len = try std.unicode.utf8Encode(u, &buf);
                            _ = try writer.write(buf[0..len]);
                        },
                    }
                }
                _ = try writer.write(tty.Text.SGR_RESET);
            }
        }
    };
}
