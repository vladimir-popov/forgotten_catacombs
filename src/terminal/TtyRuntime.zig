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
/// true if game should be rendered in the center of the terminal window:
var should_render_in_center: bool = true;
var rows_pad: u8 = 1;
var cols_pad: u8 = 1;

pub fn enableGameMode(use_mouse: bool) !void {
    try tty.Display.hideCursor();
    try tty.Display.handleWindowResize(&act, handleWindowResize);
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
        use_cheats: bool = false,
        cheat: ?g.Cheat = null,
        // true means that program should be closed
        is_exit: bool = false,

        pub fn init(
            alloc: std.mem.Allocator,
            draw_border: bool,
            render_in_center: bool,
            use_cheats: bool,
        ) !Self {
            const instance = Self{
                .alloc = alloc,
                .buffer = try DisplayBuffer(display_rows, display_cols).init(alloc),
                .menu = try Menu(display_rows, menu_cols).init(alloc),
                .cmd = try Cmd(display_cols - 2).init(alloc),
                .termios = tty.Display.enterRawMode(),
                .draw_border = draw_border,
                .use_cheats = use_cheats,
            };
            try enableGameMode(use_cheats);
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
                    .getCheat = getCheat,
                    .addMenuItem = addMenuItem,
                    .removeAllMenuItems = removeAllMenuItems,
                    .currentMillis = currentMillis,
                    .readPushedButtons = readPushedButtons,
                    .clearDisplay = clearDisplay,
                    .drawSprite = drawSprite,
                    .drawText = drawText,
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
                    } else if (self.use_cheats and ch.char == ':') {
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
            if (self.cheat) |cheat| {
                log.debug("Cheat {any} as pushed button", .{cheat});
                return .{ .game_button = .cheat, .state = .pressed };
            }
            if (try self.readKeyboardInput()) |key| {
                const game_button: ?g.Button.GameButton = switch (key) {
                    .char => switch (key.char.char) {
                        // (B) (A)
                        's', 'i' => .a,
                        'a', 'u' => .b,
                        'h' => .left,
                        'j' => .down,
                        'k' => .up,
                        'l' => .right,
                        else => null,
                    },
                    .control => switch (key.control) {
                        .LEFT => .left,
                        .DOWN => .down,
                        .UP => .up,
                        .RIGHT => .right,
                        else => null,
                    },
                    .mouse => |m| cheat: {
                        // handle mouse buttons only on press
                        if (m.is_released) return null;
                        switch (m.button) {
                            .LEFT => {
                                // -1 for border
                                self.cheat = .{ .move_player = .{
                                    .row = m.row - rows_pad - 1,
                                    .col = m.col - cols_pad - 1,
                                } };
                            },
                            .WHEEL_UP => self.cheat = .move_player_to_ladder_up,
                            .WHEEL_DOWN => self.cheat = .move_player_to_ladder_down,
                            else => return null,
                        }
                        break :cheat .cheat;
                    },
                    else => null,
                };
                if (game_button) |gbtn| {
                    self.keyboard_buffer = null;
                    return .{ .game_button = gbtn, .state = .pressed };
                } else {
                    return null;
                }
            }
            return null;
        }

        fn getCheat(ptr: *anyopaque) ?g.Cheat {
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
            mode: g.Render.DrawingMode,
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
            mode: g.Render.DrawingMode,
        ) !void {
            const self: *Self = @ptrCast(@alignCast(ptr));
            self.buffer.setAsciiText(text, position_on_display.row, position_on_display.col, mode);
        }
    };
}
