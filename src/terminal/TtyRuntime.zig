const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");

const log = std.log.scoped(.tty_runtime);

pub const Menu = @import("Menu.zig").Menu;
const Cmd = @import("Cmd.zig").Cmd;
pub const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

var window_size: tty.Display.RowsCols = undefined;
var act: std.posix.Sigaction = undefined;
/// true if the game should be rendered in the center of the terminal window:
var should_render_in_center: bool = true;
var rows_pad: u8 = 1;
var cols_pad: u8 = 1;

pub fn enableGameMode(use_mouse: bool) !void {
    try tty.Display.hideCursor();
    tty.Display.handleWindowResize(&act, handleWindowResize);
    if (use_mouse) try tty.KeyboardAndMouse.enableMouseEvents();
}

pub fn disableGameMode() !void {
    try tty.KeyboardAndMouse.disableMouseEvents();
    try tty.Display.exitFromRawMode();
    try tty.Display.showCursor();
}

fn handleWindowResize(_: i32) callconv(.C) void {
    window_size = tty.Display.getWindowSize() catch unreachable;
    tty.Display.clearScreen() catch unreachable;
    if (should_render_in_center) {
        rows_pad = (@min(window_size.rows, std.math.maxInt(u8)) - g.DISPLAY_ROWS) / 2;
        cols_pad = (@min(window_size.cols, std.math.maxInt(u8)) - g.DISPLAY_COLS) / 2;
    }
}

pub fn TtyRuntime(comptime display_rows: u8, comptime display_cols: u8) type {
    return struct {
        const Self = @This();

        const menu_cols = (display_cols - 2) / 2;

        termios: std.c.termios,
        alloc: std.mem.Allocator,
        // The main buffer to render the game
        buffer: DisplayBuffer(display_rows, display_cols),
        menu: Menu(display_rows, menu_cols),
        cmd: Cmd(display_cols - 2),
        // the last read button through readButton function.
        // it is used as a buffer to check ESC outside the readButton function
        keyboard_buffer: ?tty.KeyboardAndMouse.Button = null,
        // The border should not be drawn for DungeonGenerator
        draw_border: bool = true,
        is_dev_mode: bool = false,
        cheat: ?g.Cheat = null,
        // true means that program should be closed
        is_exit: bool = false,
        // The path to the dir with save files
        saves_dir: std.fs.Dir,

        pub fn init(
            alloc: std.mem.Allocator,
            draw_border: bool,
            render_in_center: bool,
            is_dev_mode: bool,
            use_mouse: bool,
        ) !Self {
            const instance = Self{
                .alloc = alloc,
                .buffer = try DisplayBuffer(display_rows, display_cols).init(alloc),
                .menu = try Menu(display_rows, menu_cols).init(alloc),
                .cmd = try Cmd(display_cols - 2).init(alloc),
                .termios = tty.Display.enterRawMode(),
                .draw_border = draw_border,
                .is_dev_mode = is_dev_mode,
                .saves_dir = try std.fs.cwd().makeOpenPath("save", .{}),
            };
            try enableGameMode(use_mouse);
            should_render_in_center = render_in_center;
            return instance;
        }

        pub fn deinit(self: *Self) void {
            self.buffer.deinit();
            self.menu.deinit();
            self.cmd.deinit();
            disableGameMode() catch unreachable;
        }

        pub fn runtime(self: *Self) g.Runtime {
            return .{
                .context = self,
                .vtable = &.{
                    .isDevMode = isDevMode,
                    .popCheat = popCheat,
                    .addMenuItem = addMenuItem,
                    .removeAllMenuItems = removeAllMenuItems,
                    .currentMillis = currentMillis,
                    .readPushedButtons = readPushedButtons,
                    .clearDisplay = clearDisplay,
                    .drawSprite = drawSprite,
                    .drawText = drawText,
                    .openFile = openFile,
                    .closeFile = closeFile,
                    .readFromFile = readFromFile,
                    .writeToFile = writeToFile,
                },
            };
        }

        /// Run the main loop of the game
        pub fn run(self: *Self, game: anytype) !void {
            const stdout = std.io.getStdOut().writer().any();
            handleWindowResize(0);
            while (!self.is_exit) {
                if (self.menu.is_shown) {
                    try self.menu.buffer.writeBuffer(stdout, rows_pad, cols_pad + (display_cols - menu_cols));
                    if (try readPushedButtons(self)) |btn| {
                        try self.menu.handleKeyboardButton(btn);
                    }
                } else if (self.cmd.cursor_idx > 0) {
                    self.cheat = try self.cmd.readCheat();
                    try self.cmd.buffer.writeBuffer(stdout, rows_pad + display_rows - 2, cols_pad + 1);
                } else {
                    try game.tick();
                    try self.buffer.writeBuffer(stdout, rows_pad, cols_pad);
                }
            }
        }

        fn readKeyboardInput(self: *Self) !?tty.KeyboardAndMouse.Button {
            if (tty.KeyboardAndMouse.readPressedButton()) |btn| {
                self.keyboard_buffer = btn;
                switch (btn) {
                    .control => if (btn.control == tty.KeyboardAndMouse.ControlButton.ESC) {
                        self.keyboard_buffer = null;
                        self.is_exit = true;
                    },
                    .char => |ch| if (ch.char == ' ') {
                        self.keyboard_buffer = null;
                        if (self.menu.is_shown)
                            self.menu.close()
                        else
                            try self.menu.show();
                    } else if (self.is_dev_mode and ch.char == ':') {
                        self.cmd.cleanCmd();
                    },
                    else => {},
                }
            }
            return self.keyboard_buffer;
        }

        fn currentMillis(_: *anyopaque) c_uint {
            return @truncate(@as(u64, @intCast(std.time.milliTimestamp())));
        }

        fn addMenuItem(
            ptr: *anyopaque,
            title: []const u8,
            game_object: *anyopaque,
            callback: g.Runtime.MenuItemCallback,
        ) ?*anyopaque {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.menu.addMenuItem(title, game_object, callback);
        }

        fn removeAllMenuItems(ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.menu.removeAllItems();
        }

        fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
            var self: *Self = @ptrCast(@alignCast(ptr));
            if (try self.readKeyboardInput()) |key| {
                const button: ?g.Button = switch (key) {
                    .char => switch (key.char.char) {
                        // (B) (A)
                        's', 'i' => .{ .game_button = .a, .state = .released },
                        'a', 'u' => .{ .game_button = .b, .state = .released },
                        'S', 'I' => .{ .game_button = .a, .state = .hold },
                        'A', 'U' => .{ .game_button = .b, .state = .hold },
                        'h' => .{ .game_button = .left, .state = .released },
                        'j' => .{ .game_button = .down, .state = .released },
                        'k' => .{ .game_button = .up, .state = .released },
                        'l' => .{ .game_button = .right, .state = .released },
                        else => null,
                    },
                    .control => switch (key.control) {
                        .LEFT => .{ .game_button = .left, .state = .released },
                        .DOWN => .{ .game_button = .down, .state = .released },
                        .UP => .{ .game_button = .up, .state = .released },
                        .RIGHT => .{ .game_button = .right, .state = .released },
                        else => null,
                    },
                    .mouse => |m| {
                        // handle mouse buttons only on press
                        if (m.is_released) return null;
                        switch (m.button) {
                            .LEFT => {
                                // -1 for border
                                self.cheat = .{ .goto = .{
                                    .row = m.row - rows_pad - 1,
                                    .col = m.col - cols_pad - 1,
                                } };
                            },
                            .WHEEL_UP => self.cheat = .move_player_to_ladder_up,
                            .WHEEL_DOWN => self.cheat = .move_player_to_ladder_down,
                            else => return null,
                        }
                        return null;
                    },
                    else => null,
                };
                if (button) |btn| {
                    self.keyboard_buffer = null;
                    return btn;
                } else {
                    return null;
                }
            }
            return null;
        }

        fn isDevMode(ptr: *anyopaque) bool {
            const self: *Self = @ptrCast(@alignCast(ptr));
            return self.is_dev_mode;
        }

        fn popCheat(ptr: *anyopaque) ?g.Cheat {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const cheat = self.cheat;
            self.cheat = null;
            return cheat;
        }

        fn clearDisplay(ptr: *anyopaque) !void {
            try tty.Display.clearScreen();
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.buffer.cleanAndWrap();
        }

        fn drawSprite(
            ptr: *anyopaque,
            symbol: u21,
            position_on_display: p.Point,
            mode: g.DrawingMode,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            // the buffer used indexes begun from 0, but the position coordinates begun from 1
            // we do not convert them here because we need a margin for border
            self.buffer.setSymbol(symbol, position_on_display.row, position_on_display.col, mode);
        }

        fn drawText(
            ptr: *anyopaque,
            text: []const u8,
            position_on_display: p.Point,
            mode: g.DrawingMode,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.buffer.setAsciiText(text, position_on_display.row, position_on_display.col, mode);
        }

        fn openFile(ptr: *anyopaque, file_path: []const u8, mode: g.Runtime.FileMode) anyerror!*anyopaque {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const file = try self.alloc.create(std.fs.File);
            switch (mode) {
                .read => file.* = try self.saves_dir.openFile(file_path, .{ .mode = std.fs.File.OpenMode.read_only }),
                .write => file.* = try self.saves_dir.createFile(file_path, .{}),
            }
            return file;
        }

        fn closeFile(ptr: *anyopaque, file_ptr: *anyopaque) void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
            file.close();
            self.alloc.destroy(file);
        }

        fn readFromFile(_: *anyopaque, file_ptr: *anyopaque, buffer: []u8) anyerror!usize {
            const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
            return try file.read(buffer);
        }

        fn writeToFile(_: *anyopaque, file_ptr: *anyopaque, bytes: []const u8) anyerror!usize {
            const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
            return try file.write(bytes);
        }
    };
}
