const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const log = std.log.scoped(.cmd);

const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

pub fn Cmd(comptime cols: u8) type {
    return struct {
        const Self = @This();

        buffer: DisplayBuffer(1, cols),
        // the position of the cursor in the buffer
        cursor_idx: usize = 0,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{ .buffer = try DisplayBuffer(1, cols).init(alloc) };
        }

        pub fn deinit(self: Self) void {
            self.buffer.deinit();
        }

        pub fn showCmd(self: *Self) !void {
            self.cursor_idx = 1;
            self.buffer.setSymbol(':', 0, 0, .normal);
            for (1..self.buffer.cols) |col| {
                self.buffer.setSymbol(' ', 0, col, .normal);
            }
        }

        pub fn readCheat(self: *Self) !?g.Cheat {
            if (tty.KeyboardAndMouse.readPressedButton()) |key| {
                switch (key) {
                    .control => switch (key.control) {
                        .ESC => {
                            self.cursor_idx = 0;
                        },
                        .BACKSPACE => if (self.cursor_idx > 0) {
                            self.cursor_idx -= 1;
                            self.buffer.setSymbol(' ', 0, self.cursor_idx, .normal);
                        },
                        .ENTER => {
                            var buf: [cols]u8 = undefined;
                            for (0..self.cursor_idx) |col| {
                                buf[col] = @truncate(self.buffer.lines[0][col + 1].symbol);
                            }
                            const cheat = g.Cheat.parse(buf[0..self.cursor_idx - 1]);
                            log.debug("Cheat entered: '{s}'; parsed as: {any}", .{buf[0..self.cursor_idx - 1], cheat});
                            self.cursor_idx = 0;
                            return cheat;
                        },
                        else => {},
                    },
                    .char => |ch| if (self.cursor_idx < self.buffer.cols - 1) {
                        self.buffer.setSymbol(ch.char, 0, self.cursor_idx, .normal);
                        self.cursor_idx += 1;
                    },
                    else => {},
                }
            }
            return null;
        }
    };
}
