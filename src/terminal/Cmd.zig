const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const log = std.log.scoped(.cmd);

const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

const prompt = ':';

pub fn Cmd(comptime cols: u8) type {
    return struct {
        const Self = @This();

        buffer: DisplayBuffer(1, cols),
        /// The position of the cursor in the **buffer**.
        /// 0 means the position of the prompt ':'.
        /// The command line should be hidden if this index is 0.
        cursor_idx: usize = 0,
        /// The list of available cheats in string form
        suggestions: [g.Cheat.count + 1][]const u8 = .{""} ++ g.Cheat.allAsStrings(),
        /// The index of the appropriate to the current input cheat
        suggestion_idx: u8 = 0,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{ .buffer = try DisplayBuffer(1, cols).init(alloc) };
        }

        pub fn deinit(self: Self) void {
            self.buffer.deinit();
        }

        pub fn cleanCmd(self: *Self) void {
            self.cursor_idx = 1;
            self.buffer.setSymbol(prompt, 0, 0, .normal);
            self.cleanBufferAfterCursor();
        }

        inline fn cleanBufferAfterCursor(self: *Self) void {
            for (self.cursor_idx..self.buffer.cols) |col| {
                self.buffer.setSymbol(' ', 0, col, .normal);
            }
        }

        pub fn readCheat(self: *Self) !?g.Cheat {
            if (tty.KeyboardAndMouse.readPressedButton()) |key| {
                switch (key) {
                    .control => switch (key.control) {
                        .ESC => {
                            self.cursor_idx = 0;
                            self.suggestion_idx = 0;
                            return null;
                        },
                        .BACKSPACE => if (self.cursor_idx > 0) {
                            self.cursor_idx -= 1;
                            self.suggestion_idx = 0;
                            self.buffer.setSymbol(' ', 0, self.cursor_idx, .normal);
                        },
                        .TAB => {
                            if (self.suggestion_idx < self.suggestions.len - 1)
                                self.suggestion_idx += 1
                            else
                                self.suggestion_idx = 0;
                        },
                        .ENTER => {
                            // read entered part
                            var buf: [cols]u8 = undefined;
                            for (0..self.cursor_idx) |col| {
                                buf[col] = @truncate(self.buffer.lines[0][col + 1].symbol);
                            }
                            var buf_len = self.cursor_idx - 1;
                            // read suggested part
                            while (buf_len + 1 < cols and self.buffer.lines[0][buf_len + 1].mode == .inverted) {
                                buf[buf_len] = @truncate(self.buffer.lines[0][buf_len + 1].symbol);
                                buf_len += 1;
                            }
                            if (g.Cheat.parse(buf[0..buf_len])) |cheat| {
                                log.debug(
                                    "Cheat entered: '{s}'; parsed as: {any}",
                                    .{ buf[0 .. self.cursor_idx - 1], cheat },
                                );
                                self.cursor_idx = 0;
                                self.suggestion_idx = 0;
                                return cheat;
                            } else if (self.buffer.lines[0][self.cursor_idx].mode == .inverted) {
                                // just apply suggestion and continue entering the args for the cheat
                                while (self.buffer.lines[0][self.cursor_idx].mode == .inverted) {
                                    self.buffer.lines[0][self.cursor_idx].mode = .normal;
                                    self.cursor_idx += 1;
                                }
                                self.buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
                                return null;
                            } else {
                                self.cursor_idx = 0;
                                self.suggestion_idx = 0;
                                return null;
                            }
                        },
                        else => {},
                    },
                    .char => |ch| if (self.cursor_idx < self.buffer.cols - 1) {
                        self.buffer.setSymbol(ch.char, 0, self.cursor_idx, .normal);
                        self.cursor_idx += 1;
                    },
                    else => {},
                }
                if (self.findSuggestion(self.suggestion_idx)) |i| {
                    self.suggestion_idx = i;
                    self.showSuggestion(self.suggestions[i]);
                } else {
                    self.cleanBufferAfterCursor();
                }
            }
            return null;
        }

        fn findSuggestion(self: Self, idx: usize) ?u8 {
            var buf: [cols]u8 = undefined;
            for (0..self.cursor_idx) |col| {
                buf[col] = @truncate(self.buffer.lines[0][col + 1].symbol);
            }
            var i: usize = idx;
            while (true) {
                if (self.cursor_idx > 0 and
                    std.mem.startsWith(u8, self.suggestions[i], buf[0 .. self.cursor_idx - 1]))
                {
                    log.debug(
                        "Suggestion: '{s}' at index {d}",
                        .{ self.suggestions[i], self.suggestion_idx },
                    );
                    return @intCast(i);
                } else if (self.cursor_idx > 0) {
                    log.debug(
                        "Skip suggestion '{s}' for the input '{s}'",
                        .{ self.suggestions[i], buf[0 .. self.cursor_idx - 1] },
                    );
                }
                i = if (i < self.suggestions.len - 1) i + 1 else 0;
                if (i == idx) break;
            }
            return null;
        }

        fn showSuggestion(self: Self, suggestion: []const u8) void {
            for (self.cursor_idx..cols) |i| {
                if (i <= suggestion.len) {
                    self.buffer.setSymbol(suggestion[i - 1], 0, i, .inverted);
                } else {
                    self.buffer.setSymbol(' ', 0, i, .normal);
                }
            }
        }
    };
}
