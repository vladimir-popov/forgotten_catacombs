const std = @import("std");
const fmt = std.fmt;
const c = std.c;

pub var original_termios: c.termios = undefined;

/// Functions and constants for format text and produce special sequences.
pub const Text = struct {
    const ESC = '\x1b';

    // ED - Erase Display
    const ED_FROM_START = csi("J");
    const ED_TO_END = csi("1J");
    const ED_FULL = csi("2J");

    // SM – Set Mode
    const SM_SHOW_CU = csi("?25h");

    // RM – Reset Mode
    const RM_HIDE_CU = csi("?25l");

    // CUP – Cursor Position
    const CUP = csi("H");

    // DSR – Device Status Report
    const DSR_GET_POSISION = csi("6n");

    // SGR – Select Graphic Rendition
    // Text decoration
    const SGR_RESET = csi("m");
    const SGR_BOLD = csi("1m");
    const SGR_ITALIC = csi("3m");
    const SGR_UNDERLINE = csi("4m");
    const SGR_INVERT_COLORS = csi("7m");

    pub inline fn cursorRight(comptime count: u16) *const [fmt.count("\x1b[{d}C", .{count}):0]u8 {
        comptime {
            return fmt.comptimePrint("\x1b[{d}C", .{count});
        }
    }

    pub inline fn cursorDown(comptime count: u16) *const [fmt.count("\x1b[{d}B", .{count}):0]u8 {
        comptime {
            return fmt.comptimePrint("\x1b[{d}B", .{count});
        }
    }

    pub inline fn setCursorPosition(comptime row: u8, comptime col: u8) *const [fmt.count("\x1b[{d};{d}H", .{ row, col }):0]u8 {
        comptime {
            return fmt.comptimePrint("\x1b[{d};{d}H", .{ row, col });
        }
    }

    pub inline fn normal(comptime str: []const u8) *const [3 + str.len:0]u8 {
        comptime {
            return fmt.comptimePrint("{s}{s}", .{ SGR_RESET, str });
        }
    }

    pub inline fn bold(comptime str: []const u8) *const [7 + str.len:0]u8 {
        comptime {
            return fmt.comptimePrint("{s}{s}{s}", .{ SGR_BOLD, str, SGR_RESET });
        }
    }

    pub inline fn inverted(comptime str: []const u8) *const [7 + str.len:0]u8 {
        comptime {
            return fmt.comptimePrint("{s}{s}{s}", .{ SGR_INVERT_COLORS, str, SGR_RESET });
        }
    }

    pub inline fn italic(comptime str: []const u8) *const [7 + str.len:0]u8 {
        comptime {
            return fmt.comptimePrint("{s}{s}{s}", .{ SGR_ITALIC, str, SGR_RESET });
        }
    }

    pub inline fn underline(comptime str: []const u8) *const [7 + str.len:0]u8 {
        comptime {
            return fmt.comptimePrint("{s}{s}{s}", .{ SGR_UNDERLINE, str, SGR_RESET });
        }
    }

    /// Control Sequence Introducer
    inline fn csi(comptime sfx: []const u8) *const [2 + sfx.len:0]u8 {
        comptime {
            return fmt.comptimePrint("\x1b[{s}", .{sfx});
        }
    }

    pub fn writeSetCursorPosition(writer: std.io.AnyWriter, row: u16, col: u16) !void {
        try std.fmt.format(writer, "\x1b[{d};{d}H", .{ row, col });
    }
};

pub const Display = struct {
    pub const Error = error{ GettingCursoreError, WritenNotAllBytes };

    pub const RowsCols = struct {
        rows: u16,
        cols: u16,
    };

    pub fn enterRawMode() c.termios {
        _ = c.tcgetattr(c.STDIN_FILENO, &original_termios);
        // copy struct:
        var raw = original_termios;

        // Remove some Local flags:

        //  ECHO   - used to not show printed symbol;
        raw.lflag.ECHO = false;
        //  ICANON - used to read input byte-by-byte, instead of line-byline;
        raw.lflag.ICANON = false;
        //  IEXTEN - used to tell to the terminal to wait an another character
        //           (Ctrl-V);
        raw.lflag.IEXTEN = false;
        //  ISIG   - used to handle SIGINT (Ctrl-C) and SIGTSTP (Ctrl-Z) signals,
        //           here we do not exclude them for safety;

        // Remove some Input flags:

        //  BRKINT - turns on break condition;
        raw.iflag.BRKINT = false;
        //  ICRNL  - used to translate '\r' to '\n';
        raw.iflag.ICRNL = false;
        //  INPCK  - enables parity checking, which doesn’t seem to apply to modern
        //           terminal emulators;
        raw.iflag.INPCK = false;
        //  ISTRIP - causes the 8th bit of each input byte to be stripped, meaning
        //           it will set it to 0. This is probably already turned off;
        raw.iflag.ISTRIP = false;
        //  IXON   - it's for handle XOFF (Ctrl-S) and XON (Ctrl-Q) signals, which
        //           are used for software control and not actual for today;
        raw.iflag.IXON = false;

        // Remove some Output flags:

        //  OPOST - used to translate '\n' to '\r\n';
        raw.oflag.OPOST = false;

        // Set the character size to 8 bits per byte.
        // raw.cflag |= (c.tc_cflag_t.CS8);

        // The VMIN value sets the minimum number of bytes
        // of input needed before read() can return
        raw.cc[@intFromEnum(c.V.MIN)] = 0;

        // The VTIME value sets the maximum amount of time
        // to wait before read() returns.
        // It is in tenths of a second.
        // So 1 is equals to 1/10 of a second, or 100 milliseconds.
        raw.cc[@intFromEnum(c.V.TIME)] = 1;

        _ = c.tcsetattr(c.STDIN_FILENO, .FLUSH, &raw);

        return original_termios;
    }

    pub fn exitFromRawMode() !void {
        try clearScreen();
        try showCursor();
        _ = c.tcsetattr(c.STDIN_FILENO, .FLUSH, &original_termios);
    }

    pub inline fn write(str: []const u8) !void {
        if (c.write(c.STDOUT_FILENO, str.ptr, str.len) != str.len)
            return error.WritenNotAllBytes;
    }

    pub const writer = std.io.AnyWriter{ .context = undefined, .writeFn = writeFn };
    fn writeFn(_: *const anyopaque, bytes: []const u8) anyerror!usize {
        return @intCast(c.write(c.STDOUT_FILENO, bytes.ptr, bytes.len));
    }

    pub fn clearScreen() !void {
        // Put cursor to the left upper corner
        try write(Text.CUP);
        // Erase all lines on the screen
        try write(Text.ED_FROM_START);
    }

    pub inline fn setCursorPosition(row: u8, col: u8) void {
        _ = c.printf("\x1b[%d;%dH", row, col);
    }

    pub fn hideCursor() !void {
        try write(Text.RM_HIDE_CU);
    }

    pub fn showCursor() !void {
        try write(Text.SM_SHOW_CU);
    }

    /// Returns position of the cursor
    pub fn getCursorPosition() !RowsCols {
        try write(Text.DSR_GET_POSISION);
        var buf: [32]u8 = undefined;
        var i: u8 = 0;
        while (i < buf.len - 1) {
            if (c.read(c.STDIN_FILENO, &buf, 1) != 1)
                break;
            if (buf[i] == 'R')
                break;
            i += 1;
        }
        buf[i] = 0;
        if (buf[0] != Text.ESC or buf[1] != '[')
            return error.GettingCursoreError;
        if (std.mem.indexOfScalar(u8, buf[2..], ';')) |idx| {
            return .{
                .rows = try std.fmt.parseInt(u8, buf[2..idx], 10),
                .cols = try std.fmt.parseInt(u8, buf[idx + 1 ..], 10),
            };
        } else {
            return error.GettingCursoreError;
        }
    }

    /// Returns count of rows and cols of the current window
    pub fn getWindowSize() !RowsCols {
        var ws: c.winsize = std.mem.zeroes(c.winsize);
        if (c.ioctl(c.STDOUT_FILENO, std.posix.system.T.IOCGWINSZ, &ws) == 1 or ws.ws_col == 0) {
            try write(Text.cursorDown(999) ++ Text.cursorRight(999));
            return try getCursorPosition();
        } else {
            return .{ .rows = ws.ws_row, .cols = ws.ws_col };
        }
    }

    pub fn handleWindowResize(act: *std.posix.Sigaction, handler: *align(1) const fn (i32) callconv(.C) void) !void {
        act.flags = std.posix.SA.RESTART;
        act.handler = .{ .handler = handler };
        act.mask = std.posix.empty_sigset;
        try std.posix.sigaction(std.posix.SIG.WINCH, act, null);
    }
};

pub const Keyboard = struct {
    /// The not printable control buttons
    pub const ControlButton = enum(u8) {
        ENTER = 13,
        ESC = 27,
        BACKSPACE = 127,
        UP = 'A',
        DOWN = 'B',
        LEFT = 'D',
        RIGHT = 'C',

        pub inline fn code(self: ControlButton) u8 {
            return @intFromEnum(self);
        }
    };

    /// A keyboard buttons with printable character
    pub const CharButton = struct { char: u8 };

    /// Read code of a pressed keyboard button
    pub const PressedButton = struct {
        bytes: [3]u8,
        len: usize,

        pub fn button(self: @This()) Button {
            if (self.len == 1) {
                switch (self.bytes[0]) {
                    ControlButton.ESC.code() => return Button{ .control = .ESC },
                    ControlButton.ENTER.code() => return Button{ .control = .ENTER },
                    ControlButton.BACKSPACE.code() => return Button{ .control = .BACKSPACE },
                    ' '...'~' => return Button{ .char = CharButton{ .char = self.bytes[0] } },
                    else => return Button{ .unknown = self },
                }
            }
            if (self.len == 3) {
                switch (self.bytes[2]) {
                    ControlButton.UP.code() => return Button{ .control = .UP },
                    ControlButton.DOWN.code() => return Button{ .control = .DOWN },
                    ControlButton.LEFT.code() => return Button{ .control = .LEFT },
                    ControlButton.RIGHT.code() => return Button{ .control = .RIGHT },
                    else => return Button{ .unknown = self },
                }
            }
            return Button{ .unknown = self };
        }
    };

    pub const ButtonTag = enum { control, char, unknown };

    /// Keyboard buttons
    pub const Button = union(ButtonTag) {
        control: ControlButton,
        char: CharButton,
        unknown: PressedButton,

        pub fn eql(self: Button, maybe_other: ?Button) bool {
            if (maybe_other) |other| {
                if (@intFromEnum(self) != @intFromEnum(other))
                    return false;

                return switch (self) {
                    .control => self.control.code() == other.control.code(),
                    .char => self.char.char == other.char.char,
                    .unknown => std.mem.eql(u8, &self.unknown.bytes, &other.unknown.bytes),
                };
            }
            return false;
        }
    };

    pub fn readPressedButton() ?Button {
        var buffer: [3]u8 = undefined;
        const len = c.read(c.STDIN_FILENO, &buffer, buffer.len);
        if (len > 0) {
            const btn = PressedButton{ .bytes = buffer, .len = @intCast(len) };
            return btn.button();
        } else {
            return null;
        }
    }

    pub fn isKeyPressed(comptime expected: Button) bool {
        if (readPressedButton()) |btn| {
            const expected_tag = @as(ButtonTag, expected);
            const actual_tag = @as(ButtonTag, btn);
            if (expected_tag != actual_tag)
                return false;
            switch (expected_tag) {
                .char => return btn.char == expected.char,
                .control => return btn.control == expected.control,
                .unknown => return std.mem.eql(u8, btn.unknown.bytes, expected.unknown.bytes),
            }
        } else {
            return false;
        }
    }
};
