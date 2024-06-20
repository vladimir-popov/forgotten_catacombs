const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game");
const tty = @import("tty.zig");
const utf8 = @import("utf8");

const log = std.log.scoped(.runtime);

const Self = @This();

var window_size: tty.Display.RowsCols = undefined;
var act: std.posix.Sigaction = undefined;
/// true if game should be rendered in the center of the terminal window:
var should_render_in_center: bool = true;
var rows_pad: u16 = 0;
var cols_pad: u16 = 0;

alloc: std.mem.Allocator,
// used to accumulate the buffer every run-loop circle
arena: std.heap.ArenaAllocator,
rand: std.Random,
buffer: utf8.Buffer,
termios: std.c.termios,
// the last read button through readButton function.
// it is used as a buffer to check ESC outside the readButton function
prev_key: ?tty.Keyboard.Button = null,
pressed_at: i64 = 0,

pub fn init(alloc: std.mem.Allocator, rand: std.Random, render_in_center: bool) !Self {
    const instance = Self{
        .alloc = alloc,
        .arena = std.heap.ArenaAllocator.init(alloc),
        .rand = rand,
        .buffer = undefined,
        .termios = tty.Display.enterRawMode(),
    };
    try tty.Display.hideCursor();
    try tty.Display.handleWindowResize(&act, handleWindowResize);
    should_render_in_center = render_in_center;
    return instance;
}

pub fn deinit(self: *Self) void {
    tty.Display.exitFromRawMode() catch unreachable;
    tty.Display.showCursor() catch unreachable;
    _ = self.arena.reset(.free_all);
}

/// Run the main loop of the game
pub fn run(self: *Self, game_session: anytype) !void {
    handleWindowResize(0);
    while (!self.isExit()) {
        self.buffer = utf8.Buffer.init(self.arena.allocator());
        try game_session.*.tick();
        try self.writeBuffer(tty.Display.writer);
        _ = self.arena.reset(.retain_capacity);
    }
}

fn handleWindowResize(_: i32) callconv(.C) void {
    window_size = tty.Display.getWindowSize() catch unreachable;
    tty.Display.clearScreen() catch unreachable;
    if (should_render_in_center) {
        rows_pad = (window_size.rows - game.DISPLPAY_ROWS) / 2;
        cols_pad = (window_size.cols - game.DISPLPAY_COLS) / 2;
    }
}

fn isExit(self: Self) bool {
    if (self.prev_key) |btn| {
        switch (btn) {
            .control => return btn.control == tty.Keyboard.ControlButton.ESC,
            else => return false,
        }
    } else {
        return false;
    }
}

fn writeBuffer(self: Self, writer: std.io.AnyWriter) !void {
    for (self.buffer.lines.items, rows_pad..) |line, i| {
        try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
        _ = try writer.write(line.bytes.items);
    }
}

pub fn any(self: *Self) game.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .rand = self.rand,
        .vtable = &.{
            .currentMillis = currentMillis,
            .readButtons = readButtons,
            .drawUI = drawUI,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .drawLabel = drawLabel,
        },
    };
}

fn currentMillis(_: *anyopaque) i64 {
    return std.time.milliTimestamp();
}

fn readButtons(ptr: *anyopaque) anyerror!?game.AnyRuntime.Buttons {
    var self: *Self = @ptrCast(@alignCast(ptr));
    const prev_key = self.prev_key;
    if (tty.Keyboard.readPressedButton()) |key| {
        self.prev_key = key;
        const known_key_code: ?game.AnyRuntime.Buttons.Code = switch (key) {
            .char => switch (key.char.char) {
                ' ' => game.AnyRuntime.Buttons.A,
                'f' => game.AnyRuntime.Buttons.B,
                'd' => game.AnyRuntime.Buttons.A,
                'h' => game.AnyRuntime.Buttons.Left,
                'j' => game.AnyRuntime.Buttons.Down,
                'k' => game.AnyRuntime.Buttons.Up,
                'l' => game.AnyRuntime.Buttons.Right,
                else => null,
            },
            .control => switch (key.control) {
                .LEFT => game.AnyRuntime.Buttons.Left,
                .DOWN => game.AnyRuntime.Buttons.Down,
                .UP => game.AnyRuntime.Buttons.Up,
                .RIGHT => game.AnyRuntime.Buttons.Right,
                else => null,
            },
            else => null,
        };
        if (known_key_code) |code| {
            const now = std.time.milliTimestamp();
            const delay = now - self.pressed_at;
            self.pressed_at = now;
            var state: game.AnyRuntime.Buttons.State = .pressed;
            if (key.eql(prev_key)) {
                if (delay < game.AnyRuntime.DOUBLE_PRESS_DELAY_MS)
                    state = .double_pressed
                else if (delay > game.AnyRuntime.HOLD_DELAY_MS)
                    state = .hold;
            }
            return .{ .code = code, .state = state };
        } else {
            self.pressed_at = 0;
            return null;
        }
    }
    return null;
}

fn drawUI(ptr: *anyopaque) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.buffer.addLine("╔" ++ "═" ** game.DISPLPAY_COLS ++ "╗");
    for (0..game.DISPLPAY_ROWS) |_| {
        try self.buffer.addLine("║" ++ " " ** game.DISPLAY_DUNG_COLS ++ "║" ++ " " ** (game.STATS_COLS - 1) ++ "║");
    }
    try self.buffer.addLine("╚" ++ "═" ** game.DISPLPAY_COLS ++ "╝");
    try self.buffer.lines.items[0].set(game.DISPLAY_DUNG_COLS + 1, '╦');
    try self.buffer.lines.items[game.DISPLPAY_ROWS + 1].set(game.DISPLAY_DUNG_COLS + 1, '╩');
}

fn drawDungeon(ptr: *anyopaque, screen: *const game.Screen, dungeon: *const game.Dungeon) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    const buffer = &self.buffer;
    var itr = dungeon.cellsInRegion(screen.region) orelse return;
    var line = try self.alloc.alloc(u8, screen.region.cols);
    defer self.alloc.free(line);

    var idx: u8 = 0;
    var row: u8 = 1;
    while (itr.next()) |cell| {
        line[idx] = switch (cell) {
            .nothing => ' ',
            .floor => '.',
            .wall => '#',
            .door => |door| if (door == .opened) '\'' else '+',
        };
        idx += 1;
        if (itr.cursor.col == itr.region.top_left.col) {
            // try buffer.addLine(line);
            try buffer.mergeLine(line, row, 1);
            @memset(line, 0);
            idx = 0;
            row += 1;
        }
    }
}

fn drawSprite(
    ptr: *anyopaque,
    screen: *const game.Screen,
    sprite: *const game.Sprite,
    position: *const game.Position,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        var self: *Self = @ptrCast(@alignCast(ptr));
        const r = position.point.row - screen.region.top_left.row + 1;
        const c = position.point.col - screen.region.top_left.col + 1;
        try self.buffer.mergeLine(sprite.letter, r, c);
    }
}

fn drawLabel(ptr: *anyopaque, label: []const u8, row: u8, col: u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.buffer.mergeLine(label, row, col);
}
