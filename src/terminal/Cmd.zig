const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const log = std.log.scoped(.cmd);

const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

const prompt = ':';

const cheats_suggestions: [g.Cheat.count][]const u8 = g.Cheat.allAsStrings();

const Autocompletion = struct {
    /// The list of available suggestions according to the context
    suggestions: []const []const u8 = &cheats_suggestions,
    /// The index of the appropriate to the current input and context suggestion
    suggestion_idx: usize = 0,
    context: ?g.Cheat.Tag,
    prefix: []const u8,

    const all_cheats: Autocompletion = .{ .suggestions = &cheats_suggestions, .context = null, .prefix = "" };

    fn initForCheat(cheat: g.Cheat.Tag) Autocompletion {
        return .{
            .context = cheat,
            .prefix = g.Cheat.toString(cheat),
            .suggestions = if (g.Cheat.suggestions(cheat)) |ss| ss else &.{},
        };
    }

    fn nextSuggestion(self: *Autocompletion) void {
        if (self.suggestion_idx < self.suggestions.len - 1)
            self.suggestion_idx += 1
        else
            self.suggestion_idx = 0;
    }

    /// Returns a non empty suggested part additionally to the input
    fn findSuggestion(self: *Autocompletion, whole_input: []const u8) ?[]const u8 {
        // skip not enough input
        if (whole_input.len <= self.prefix.len) return null;

        // skip an input with wrong context
        if (!std.mem.startsWith(u8, whole_input, self.prefix)) return null;

        const input = std.mem.trimStart(u8, whole_input[self.prefix.len..], " ");

        var i: usize = self.suggestion_idx;
        // looking for suggestion
        while (self.suggestions.len > 0) {
            if (std.mem.startsWith(u8, self.suggestions[i], input)) {
                self.suggestion_idx = i;
                const suggested_part = self.suggestions[i][input.len..];
                log.debug(
                    "Suggestion: '{s}' at index {d}. Suggested part is '{s}'",
                    .{ self.suggestions[i], i, suggested_part },
                );
                if (suggested_part.len == 0) {
                    if (g.Cheat.parse(self.suggestions[i])) |cheat_or_tag| {
                        if (cheat_or_tag == .tag) {
                            self.* = .initForCheat(cheat_or_tag.tag);
                        }
                    }
                    return null;
                } else {
                    return suggested_part;
                }
            } else {
                log.debug(
                    "Skip suggestion '{s}' for the input '{s}' (actual is '{s}'). The prefix is '{s}'",
                    .{ self.suggestions[i], whole_input, input, self.prefix },
                );
            }
            i = if (i < self.suggestions.len - 1) i + 1 else 0;
            if (i == self.suggestion_idx) break;
        }
        return null;
    }
};

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
                .completion = .all_cheats,
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

        /// Copies a content of the buffer from 0 till the `cursor_idx`.
        fn enteredContent(self: Self, buf: []u8) usize {
            for (0..self.cursor_idx) |col| {
                buf[col] = @truncate(self.display_buffer.lines[0][col + 1].symbol);
            }
            return self.cursor_idx - 1;
        }

        /// Invokes while the `cursor_idx` > 0.
        /// Returns either a parsed cheat, or null.
        /// The `cursor_idx` == 0 means that the cmd should be closed.
        pub fn readCheat(self: *Self) ?g.Cheat {
            if (tty.KeyboardAndMouse.readPressedButton()) |key| {
                // handle pressed button
                switch (key) {
                    .char => |ch| if (self.cursor_idx < self.display_buffer.cols - 1) {
                        // echo the symbol
                        self.display_buffer.setSymbol(ch.char, 0, self.cursor_idx, .normal);
                        self.cursor_idx += 1;
                        if (self.cursor_idx < self.display_buffer.cols - 1)
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
                    },
                    .control => switch (key.control) {
                        .ESC => {
                            self.cursor_idx = 0;
                            self.completion = .all_cheats;
                            return null;
                        },
                        .BACKSPACE => if (self.cursor_idx > 0) {
                            self.cursor_idx -= 1;
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);

                            // reset completion ?
                            var buf: [cols]u8 = undefined;
                            const buf_len = self.enteredContent(&buf);
                            if (!std.mem.startsWith(u8, buf[0..buf_len], self.completion.prefix))
                                self.completion = .all_cheats;
                        },
                        .TAB => self.completion.nextSuggestion(),
                        .ENTER => {
                            // apply a suggested part (change highlighting and move the cursor)
                            while (self.display_buffer.lines[0][self.cursor_idx].mode == .inverted) {
                                self.display_buffer.lines[0][self.cursor_idx].mode = .normal;
                                self.cursor_idx += 1;
                            }
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .normal);
                            self.cursor_idx += 1;
                            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);

                            // read the input
                            var buf: [cols]u8 = undefined;
                            const buf_len = self.enteredContent(&buf);
                            const input = buf[0..buf_len];

                            log.debug("Entered content is '{s}'", .{input});

                            // Try to parse a cheat
                            if (g.Cheat.parse(input)) |cheat_or_tag| {
                                switch (cheat_or_tag) {
                                    .cheat => |cheat| {
                                        log.debug("Input: '{s}'; parsed as the cheat {any}", .{ input, cheat });
                                        self.cursor_idx = 0;
                                        return cheat;
                                    },
                                    else => return null,
                                }
                            } // or close the cmd
                            else {
                                self.cursor_idx = 0;
                                return null;
                            }
                        },
                        else => {},
                    },
                    else => {},
                }
                // try to show a suggestion
                var buf: [cols]u8 = undefined;
                const buf_len = self.enteredContent(&buf);
                if (self.completion.findSuggestion(buf[0..buf_len])) |suggestion| {
                    // write the suggestion
                    const max_len = @min(suggestion.len, cols - self.cursor_idx);
                    for (suggestion[0..max_len], self.cursor_idx..) |s, i| {
                        self.display_buffer.setSymbol(s, 0, i, .inverted);
                    }
                    // clean the rest cmd
                    for (self.cursor_idx + suggestion.len..cols) |i| {
                        self.display_buffer.setSymbol(' ', 0, i, .normal);
                    }
                } else {
                    self.cleanBufferAfterCursor();
                }
            }
            return null;
        }

        inline fn cleanBufferAfterCursor(self: *Self) void {
            for (self.cursor_idx..self.display_buffer.cols) |col| {
                self.display_buffer.setSymbol(' ', 0, col, .normal);
            }
            self.display_buffer.setSymbol(' ', 0, self.cursor_idx, .inverted);
        }
    };
}
