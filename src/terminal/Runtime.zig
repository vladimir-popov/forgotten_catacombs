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
        try game_session.tick();
        try self.writeBuffer(tty.Display.writer);
    }
}

fn clearScreen(ptr: *anyopaque) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    _ = self.arena.reset(.retain_capacity);
    self.buffer = utf8.Buffer.init(self.arena.allocator());
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
            .readPushedButtons = readPushedButtons,
            .clearScreen = clearScreen,
            .drawUI = drawUI,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .drawLabel = drawLabel,
        },
    };
}

fn currentMillis(_: *anyopaque) c_uint {
    return @truncate(@as(u64, @intCast(std.time.milliTimestamp())));
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?game.Buttons {
    var self: *Self = @ptrCast(@alignCast(ptr));
    const prev_key = self.prev_key;
    if (tty.Keyboard.readPressedButton()) |key| {
        self.prev_key = key;
        const known_key_code: ?game.Buttons.Code = switch (key) {
            .char => switch (key.char.char) {
                // (B) (A)
                ' ', 's' => game.Buttons.A,
                'b', 'a' => game.Buttons.B,
                'h' => game.Buttons.Left,
                'j' => game.Buttons.Down,
                'k' => game.Buttons.Up,
                'l' => game.Buttons.Right,
                else => null,
            },
            .control => switch (key.control) {
                .LEFT => game.Buttons.Left,
                .DOWN => game.Buttons.Down,
                .UP => game.Buttons.Up,
                .RIGHT => game.Buttons.Right,
                else => null,
            },
            else => null,
        };
        if (known_key_code) |code| {
            const now = std.time.milliTimestamp();
            const delay = now - self.pressed_at;
            self.pressed_at = now;
            var state: game.Buttons.State = .pushed;
            if (key.eql(prev_key)) {
                if (delay < game.Buttons.DOUBLE_PUSH_DELAY_MS)
                    state = .double_pushed
                else if (delay > game.Buttons.HOLD_DELAY_MS)
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
    const width = game.DISPLPAY_COLS + 1; // +1 for the separator between dung and stats
    try self.buffer.addLine("╔" ++ "═" ** width ++ "╗");
    for (0..game.DISPLPAY_ROWS) |_| {
        try self.buffer.addLine("║" ++ " " ** game.DISPLAY_DUNG_COLS ++ "║" ++ " " ** game.STATS_COLS ++ "║");
    }
    try self.buffer.addLine("╚" ++ "═" ** width ++ "╝");
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
    screen: *const game.Screen,
    sprite: *const game.Sprite,
    mode: game.AnyRuntime.DrawingMode,
) anyerror!void {
    if (screen.region.containsPoint(sprite.position)) {
        var self: *Self = @ptrCast(@alignCast(ptr));
        const r = sprite.position.row - screen.region.top_left.row + 1; // +1 for border
        const c = sprite.position.col - screen.region.top_left.col + 1;
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
fn drawLabel(ptr: *anyopaque, label: []const u8, absolute_position: p.Point) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    try self.buffer.mergeLine(label, absolute_position.row, absolute_position.col); // do not subtract, coz border!
}
