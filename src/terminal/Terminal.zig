const std = @import("std");
const os = std.os;
const sys = std.os.system;

const ESC = '\x1b';

/// Control Sequence Introducer
inline fn csi(comptime sfx: []const u8) *const [2 + sfx.len:0]u8 {
    comptime {
        return std.fmt.comptimePrint("\x1b[{s}", .{sfx});
    }
}

/// Moves the cursor on `count` symbols to the right.
pub inline fn cursorRight(comptime count: u8) *const [std.fmt.count("\x1b[{d}", .{count}):0]u8 {
    comptime {
        return std.fmt.comptimePrint("\x1b[{d}C", .{count});
    }
}

/// Moves the cursor on `count` symbols down.
pub inline fn cursorDown(comptime count: u8) *const [std.fmt.count("\x1b[{d}", .{count}):0]u8 {
    comptime {
        return std.fmt.comptimePrint("\x1b[{d}B", .{count});
    }
}

// zig fmt: off
// Code of some keyboard buttons:
const KeyboardButtonCode = enum(u8) {
    KB_ENTER = 13,
    KB_ESC = 27,
    KB_SPACE = 32,
    KB_BACKSPACE = 127,
    KB_UP = 'A',
    KB_DOWN = 'B',
    KB_LEFT = 'D',
    KB_RIGHT = 'C'
};
// zig fmt: on

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

pub inline fn format_set_cursor_position(writer: anytype, row: u32, col: u32) !void {
    return try std.fmt.format(writer, "\x1b[{d};{d}H", .{ row, col });
}

// DSR – Device Status Report
const DSR_GET_POSISION = csi("6n");

// SGR – Select Graphic Rendition
// Text decoration
const SGR_RESET = csi("m");
const SGR_BOLD = csi("1m");
const SGR_ITALIC = csi("3m");
const SGR_UNDERLINE = csi("4m");
const SGR_INVERT_COLORS = csi("7m");

inline fn italic(comptime str: []const u8) *const [7 + str.len:0]u8 {
    comptime {
        return std.fmt.comptimePrint("{s}{s}{s}", .{ SGR_ITALIC, str, SGR_RESET });
    }
}

inline fn bold(comptime str: []const u8) *const [7 + str.len:0]u8 {
    comptime {
        return std.fmt.comptimePrint("{s}{s}{s}", .{ SGR_BOLD, str, SGR_RESET });
    }
}

inline fn underline(comptime str: []const u8) *const [7 + str.len:0]u8 {
    comptime {
        return std.fmt.comptimePrint("{s}{s}{s}", .{ SGR_UNDERLINE, str, SGR_RESET });
    }
}

pub const PressedKeyboardButton = struct { code: [3]u8, len: usize };

pub const Terminal = struct {
    const Self = @This();

    tty: std.fs.File,
    original_termios: os.termios,

    pub fn init() !Terminal {
        const tty = try std.fs.openFileAbsolute("/dev/tty", .{ .mode = .read_write });
        errdefer tty.close();

        const original_termios = try os.tcgetattr(tty.handle);
        // copy struct:
        var raw = original_termios;

        // Remove some Local flags:
        //  ECHO   - used to not show printed symbol;
        //  ICANON - used to read input byte-by-byte, instead of line-byline;
        //  ISIG   - used to handle SIGINT (Ctrl-C) and SIGTSTP (Ctrl-Z) signals,
        //           here we do not exclude them for safety;
        //  IEXTEN - used to tell to the terminal to wait an another character
        //           (Ctrl-V);
        raw.lflag &= ~@as(sys.tcflag_t, sys.ECHO | sys.ICANON | sys.IEXTEN);

        // Remove some Input flags:
        //  BRKINT - turns on break condition;
        //  ICRNL  - used to translate '\r' to '\n';
        //  INPCK  - enables parity checking, which doesn’t seem to apply to modern
        //           terminal emulators;
        //  ISTRIP - causes the 8th bit of each input byte to be stripped, meaning
        //           it will set it to 0. This is probably already turned off;
        //  IXON   - it's for handle XOFF (Ctrl-S) and XON (Ctrl-Q) signals, which
        //           are used for software control and not actual for today;
        raw.iflag &= ~@as(sys.tcflag_t, sys.BRKINT | sys.ICRNL | sys.INPCK | sys.ISTRIP | sys.IXON);

        // Remove some Output flags:
        //  OPOST - used to translate '\n' to '\r\n';
        raw.oflag &= ~@as(sys.tcflag_t, sys.OPOST);

        // Set the character size to 8 bits per byte.
        raw.cflag |= @as(sys.tcflag_t, sys.CS8);

        // The VMIN value sets the minimum number of bytes
        // of input needed before read() can return
        raw.cc[sys.V.MIN] = 0;

        // The VTIME value sets the maximum amount of time
        // to wait before read() returns.
        // It is in tenths of a second.
        // So 1 is equals to 1/10 of a second, or 100 milliseconds.
        raw.cc[sys.V.TIME] = 1;

        try os.tcsetattr(tty.handle, .FLUSH, raw);

        return Terminal{ .tty = tty, .original_termios = original_termios };
    }

    pub fn deinit(self: Self) void {
        os.tcsetattr(self.tty.handle, .FLUSH, self.original_termios) catch unreachable;
        self.tty.close();
    }

    pub fn readPressedKey(self: Self) !PressedKeyboardButton {
        var buffer: [3]u8 = undefined;
        const len = try self.tty.read(&buffer);
        return PressedKeyboardButton{ .code = buffer, .len = len };
    }

    pub fn clearScreen(self: Self) !void {
        // Put cursor to the left upper corner
        try self.tty.write(CUP);
        // Erase all lines on the screen
        try self.tty.write(ED_FROM_START);
    }

    pub fn hide_cursor(self: Self) !void {
        try self.tty.write(RM_HIDE_CU);
    }

    pub fn show_cursor(self: Self) !void {
        try self.tty.write(SM_SHOW_CU);
    }

    pub fn set_cursor_position(self: Self, row: u32, col: u32) !void {
        try format_set_cursor_position(self.tty.writer(), row, col);
    }
};
