const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const log = std.log.scoped(.cmd);

const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

const prompt = ':';

const Autocompletion = struct {
    /// The list of available suggestions
    suggestions: []const []const u8,
    /// The index of the appropriate to the current input suggestion
    suggestion_idx: usize = 0,

    fn nextSuggestion(self: *Autocompletion) void {
        if (self.suggestion_idx < self.suggestions.len - 1)
            self.suggestion_idx += 1
        else
            self.suggestion_idx = 0;
    }

    fn findSuggestion(self: *Autocompletion, content: []const u8) ?[]const u8 {
        if (content.len == 0) return null;

        var i: usize = self.suggestion_idx;
        while (true) {
            if (std.mem.startsWith(u8, self.suggestions[i], content)) {
                log.debug("Suggestion: '{s}' at index {d}", .{ self.suggestions[i], self.suggestion_idx });
                self.suggestion_idx = i;
                return self.suggestions[i];
            } else {
                log.debug("Skip suggestion '{s}' for the input '{s}'", .{ self.suggestions[i], content });
            }
            i = if (i < self.suggestions.len - 1) i + 1 else 0;
            if (i == self.suggestion_idx) break;
        }
        return null;
    }
};

const cheats_suggestions: [g.Cheat.count + 1][]const u8 = .{""} ++ g.Cheat.allAsStrings();

pub fn Cmd(comptime cols: u8) type {
    return struct {
        const Self = @This();

        display_buffer: DisplayBuffer(1, cols),
        completion: Autocompletion,
        /// The position of the cursor in the **buffer**.
        /// 0 means the position of the prompt ':'.
        /// The command line should be hidden if this index is 0.
        /// The symbol under cursor should be inverted.
        cursor_idx: usize = 0,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{
                .display_buffer = try DisplayBuffer(1, cols).init(alloc),
                .completion = .{ .suggestions = &cheats_suggestions },
            };
        }

        pub fn deinit(self: Self) void {
            self.display_buffer.deinit();
        }

        pub fn cleanCmd(self: *Self) void {
            self.cursor_idx = 1;
            self.display_buffer.setSymbol(prompt, 0, 0, .normal);
            self.cleanBufferAfterCursor();
        }

        inline fn cleanBufferAfterCursor(self: *Self) void {
            for (self.cursor_idx..self.display_buffer.cols) |col| {
                self.display_buffer.setSymbol(' ', 0, col, .normal);
            }
            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
        }

        /// Copies a content of the buffer from 0 till the `cursor_idx`.
        fn enteredContent(self: Self, buf: []u8) usize {
            for (0..self.cursor_idx) |col| {
                buf[col] = @truncate(self.display_buffer.lines[0][col + 1].symbol);
            }
            return self.cursor_idx - 1;
        }

        // Copies a content of the buffer from 0 till the last inverted symbol.
        fn wholeContent(self: Self, buf: []u8) usize {
            var len = self.enteredContent(buf);
            // read suggested part
            while (len + 1 < cols and self.display_buffer.lines[0][len + 1].mode == .inverted) {
                // only ascii symbols can be read
                buf[len] = @truncate(self.display_buffer.lines[0][len + 1].symbol);
                len += 1;
            }
            return len;
        }

        /// Returns either a parsed cheat, or null.
        /// Reading will be continued until the `cursor_idx` become 0.
        pub fn readCheat(self: *Self) ?g.Cheat {
            if (tty.KeyboardAndMouse.readPressedButton()) |key| {
                // handle pressed button
                switch (key) {
                    .control => switch (key.control) {
                        .ESC => {
                            self.cursor_idx = 0;
                            return null;
                        },
                        .BACKSPACE => if (self.cursor_idx > 0) {
                            self.cursor_idx -= 1;
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
                        },
                        .TAB => self.completion.nextSuggestion(),
                        .ENTER => {
                            // read the whole input including a suggest part
                            var buf: [cols]u8 = undefined;
                            const buf_len = self.wholeContent(&buf);
                            if (g.Cheat.parse(buf[0..buf_len])) |cheat| {
                                log.debug(
                                    "Cheat entered: '{s}'; parsed as: {any}",
                                    .{ buf[0 .. self.cursor_idx - 1], cheat },
                                );
                                self.cursor_idx = 0;
                                return cheat;
                            } else if (self.display_buffer.lines[0][self.cursor_idx].mode == .inverted and
                                self.display_buffer.lines[0][self.cursor_idx].symbol != ' ')
                            {
                                // just apply suggestion (change highlighting)
                                // and continue entering the args for the cheat
                                while (self.display_buffer.lines[0][self.cursor_idx].mode == .inverted and
                                    self.display_buffer.lines[0][self.cursor_idx].symbol != ' ')
                                {
                                    self.display_buffer.lines[0][self.cursor_idx].mode = .normal;
                                    self.cursor_idx += 1;
                                }
                                self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .normal);
                                self.cursor_idx += 1;
                                self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
                                return null;
                            } else {
                                self.cursor_idx = 0;
                                return null;
                            }
                        },
                        else => {},
                    },
                    .char => |ch| if (self.cursor_idx < self.display_buffer.cols - 1) {
                        self.display_buffer.setSymbol(ch.char, 0, self.cursor_idx, .normal);
                        self.cursor_idx += 1;
                        if (self.cursor_idx < self.display_buffer.cols - 1)
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
                    },
                    else => {},
                }
                // try to show suggestion
                var buf: [cols]u8 = undefined;
                const buf_len = self.enteredContent(&buf);
                if (self.completion.findSuggestion(buf[0..buf_len])) |suggestion| {
                    self.showSuggestion(suggestion);
                } else {
                    self.cleanBufferAfterCursor();
                }
            }
            return null;
        }

        fn showSuggestion(self: Self, suggestion: []const u8) void {
            for (self.cursor_idx..cols) |i| {
                if (i <= suggestion.len) {
                    self.display_buffer.setSymbol(suggestion[i - 1], 0, i, .inverted);
                } else {
                    self.display_buffer.setSymbol(' ', 0, i, .normal);
                }
            }
        }
    };
}
