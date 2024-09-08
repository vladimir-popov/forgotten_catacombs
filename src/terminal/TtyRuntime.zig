const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");
const utf8 = @import("utf8.zig");

const log = std.log.scoped(.tty_runtime);

const TtyRuntime = @This();

var window_size: tty.Display.RowsCols = undefined;
var act: std.posix.Sigaction = undefined;
/// true if game should be rendered in the center of the terminal window:
var should_render_in_center: bool = true;
var rows_pad: u8 = 0;
var cols_pad: u8 = 0;

alloc: std.mem.Allocator,
// used to accumulate the buffer every run-loop circle
arena: std.heap.ArenaAllocator,
buffer: utf8.Buffer,
termios: std.c.termios,
// the last read button through readButton function.
// it is used as a buffer to check ESC outside the readButton function
prev_key: ?tty.KeyboardAndMouse.Button = null,
pressed_at: i64 = 0,
cheat: ?g.Cheat = null,

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

pub fn init(alloc: std.mem.Allocator, render_in_center: bool, use_cheats: bool) !TtyRuntime {
    const instance = TtyRuntime{
        .alloc = alloc,
        .arena = std.heap.ArenaAllocator.init(alloc),
        .buffer = undefined,
        .termios = tty.Display.enterRawMode(),
    };
    try enableGameMode(use_cheats);
    should_render_in_center = render_in_center;
    return instance;
}

pub fn deinit(self: *TtyRuntime) void {
    _ = self.arena.reset(.free_all);
    disableGameMode() catch unreachable;
}

/// Run the main loop of the game
pub fn run(self: *TtyRuntime, game: anytype) !void {
    handleWindowResize(0);
    while (!self.isExit()) {
        try game.tick();
        try self.writeBuffer(tty.stdout_writer);
    }
}

fn handleWindowResize(_: i32) callconv(.C) void {
    window_size = tty.Display.getWindowSize() catch unreachable;
    tty.Display.clearScreen() catch unreachable;
    if (should_render_in_center) {
        rows_pad = (@min(window_size.rows, std.math.maxInt(u8)) - g.DISPLAY_ROWS) / 2;
        cols_pad = (@min(window_size.cols, std.math.maxInt(u8)) - g.DISPLAY_COLS) / 2;
    }
}

fn isExit(self: TtyRuntime) bool {
    if (self.prev_key) |btn| {
        switch (btn) {
            .control => return btn.control == tty.KeyboardAndMouse.ControlButton.ESC,
            else => return false,
        }
    } else {
        return false;
    }
}

fn writeBuffer(self: TtyRuntime, writer: std.io.AnyWriter) !void {
    for (self.buffer.lines.items, rows_pad..) |line, i| {
        try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
        _ = try writer.write(line.bytes.items);
    }
}

pub fn any(self: *TtyRuntime) g.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .vtable = &.{
            .getCheat = getCheat,
            .currentMillis = currentMillis,
            .readPushedButtons = readPushedButtons,
            .clearDisplay = clearDisplay,
            .drawHorizontalBorderLine = drawHorizontalBorderLine,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .drawText = drawText,
        },
    };
}

fn currentMillis(_: *anyopaque) c_uint {
    return @truncate(@as(u64, @intCast(std.time.milliTimestamp())));
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    // const prev_key = self.prev_key;
    if (tty.KeyboardAndMouse.readPressedButton()) |key| {
        self.prev_key = key;
        const game_button: ?g.Button.GameButton = switch (key) {
            .char => switch (key.char.char) {
                // (B) (A)
                ' ', 's', 'i' => .a,
                'b', 'a', 'u' => .b,
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
                    .RIGHT => self.cheat = .refresh_screen,
                    .LEFT => {
                        // -1 for border
                        self.cheat = .{ .move_player = .{ .row = m.row - rows_pad - 1, .col = m.col - cols_pad - 1 } };
                    },
                    .WHEEL_UP => self.cheat = .move_player_to_entrance,
                    .WHEEL_DOWN => self.cheat = .move_player_to_exit,
                    else => return null,
                }
                break :cheat .cheat;
            },
            else => null,
        };
        if (game_button) |gbtn| {
            const now = std.time.milliTimestamp();
            self.pressed_at = now;
            // const delay = now - self.pressed_at;
            // var state: g.Button.State = .pressed;
            // if (key.eql(prev_key)) {
            //     if (delay < g.DOUBLE_PUSH_DELAY_MS)
            //         state = .double_pressed
            //     else if (delay > g.HOLD_DELAY_MS)
            //         state = .hold;
            // }
            return .{ .game_button = gbtn, .state = .pressed };
        } else {
            self.pressed_at = 0;
            return null;
        }
    }
    return null;
}

fn getCheat(ptr: *anyopaque) ?g.Cheat {
    const self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    return self.cheat;
}

fn clearDisplay(ptr: *anyopaque) !void {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    _ = self.arena.reset(.retain_capacity);
    self.buffer = utf8.Buffer.init(self.arena.allocator());
    // draw external border
    try self.buffer.addLine("╔" ++ "═" ** g.DISPLAY_COLS ++ "╗");
    for (0..(g.DISPLAY_ROWS)) |_| {
        try self.buffer.addLine("║" ++ " " ** g.DISPLAY_COLS ++ "║");
    }
    try self.buffer.addLine("╚" ++ "═" ** g.DISPLAY_COLS ++ "╝");
}

fn drawHorizontalBorderLine(ptr: *anyopaque, row: u8, length: u8) !void {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    const buf = "═" ** g.DISPLAY_COLS;
    // the "═" symbol takes 3 bytes 0xE2 0x95 0x90
    try self.buffer.mergeLine(buf[0 .. length * 3], row + 1, 1);
}

fn drawDungeon(ptr: *anyopaque, screen: g.Screen, dungeon: g.Dungeon) anyerror!void {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    const buffer = &self.buffer;
    var itr = dungeon.cellsInRegion(screen.region) orelse return;
    var line = try self.alloc.alloc(u8, screen.region.cols);
    defer self.alloc.free(line);

    var idx: u8 = 0;
    var row: u8 = 1;
    while (itr.next()) |cell| {
        line[idx] = switch (cell) {
            .floor => '.',
            .wall => '#',
            else => ' ',
        };
        idx += 1;
        if (itr.current_place.col == itr.region.bottomRightCol()) {
            try buffer.mergeLine(line[0..idx], row, 1);
            @memset(line, 0);
            idx = 0;
            row += 1;
        }
    }
}

fn drawSprite(
    ptr: *anyopaque,
    screen: g.Screen,
    sprite: *const g.components.Sprite,
    position: *const g.components.Position,
    mode: g.AnyRuntime.DrawingMode,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
        const r = position.point.row - screen.region.top_left.row + 1; // +1 for border
        const c = position.point.col - screen.region.top_left.col + 1;
        if (mode == .inverted) {
            var symbol: [4]u8 = undefined;
            const len = try std.unicode.utf8Encode(sprite.codepoint, &symbol);
            var buf: [12]u8 = undefined;
            try self.buffer.mergeLine(
                try std.fmt.bufPrint(&buf, tty.Text.inverted("{s}"), .{symbol[0..len]}),
                r,
                c,
            );
        } else {
            try self.buffer.set(sprite.codepoint, r, c);
        }
    }
}

// row and col - position of the lable in the window, not inside the screen!
fn drawText(
    ptr: *anyopaque,
    text: []const u8,
    absolute_position: p.Point,
    mode: g.AnyRuntime.DrawingMode,
) !void {
    const self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    const r = absolute_position.row + 1; // +1 for top border
    const c = absolute_position.col;
    var buf: [50]u8 = undefined;
    if (mode == .inverted) {
        try self.buffer.mergeLine(try std.fmt.bufPrint(&buf, tty.Text.inverted("{s}"), .{text}), r, c);
    } else {
        try self.buffer.mergeLine(try std.fmt.bufPrint(&buf, tty.Text.normal("{s}"), .{text}), r, c);
    }
}
