const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");
const utf8 = @import("utf8.zig");

const Menu = @import("Menu.zig");

const log = std.log.scoped(.tty_runtime);

const TtyRuntime = @This();

var window_size: tty.Display.RowsCols = undefined;
var act: std.posix.Sigaction = undefined;
/// true if game should be rendered in the center of the terminal window:
var should_render_in_center: bool = true;
var rows_pad: u8 = 0;
var cols_pad: u8 = 0;

termios: std.c.termios,
alloc: std.mem.Allocator,
// used to create the buffer, and can be completely free on cleanDisplay
arena: std.heap.ArenaAllocator,
// The main buffer to render the game
buffer: utf8.Buffer,
menu: Menu,
// the last read button through readButton function.
// it is used as a buffer to check ESC outside the readButton function
keyboard_buffer: ?tty.KeyboardAndMouse.Button = null,
// The border should not be drawn for DungeonGenerator
draw_border: bool = true,
cheat: ?g.Cheat = null,
is_exit: bool = false,

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

pub fn init(alloc: std.mem.Allocator, draw_border: bool, render_in_center: bool, use_cheats: bool) !TtyRuntime {
    const instance = TtyRuntime{
        .alloc = alloc,
        .arena = std.heap.ArenaAllocator.init(alloc),
        .buffer = undefined,
        .menu = Menu.init(alloc),
        .termios = tty.Display.enterRawMode(),
        .draw_border = draw_border,
    };
    try enableGameMode(use_cheats);
    should_render_in_center = render_in_center;
    return instance;
}

pub fn deinit(self: *TtyRuntime) void {
    self.menu.deinit();
    _ = self.arena.reset(.free_all);
    disableGameMode() catch unreachable;
}

/// Run the main loop of the game
pub fn run(self: *TtyRuntime, game: anytype) !void {
    handleWindowResize(0);
    while (!self.is_exit) {
        if (self.menu.is_shown) {
            if (try readPushedButtons(self)) |btn| {
                try self.menu.handleKeyboardButton(btn);
            }
            // menu can be closed after reading keyboard
            if (self.menu.is_shown)
                try writeBuffer(self.menu.buffer, tty.stdout_writer);
        } else {
            try game.tick();
            try writeBuffer(self.buffer, tty.stdout_writer);
        }
    }
}

fn reedKeyboardInput(self: *TtyRuntime) !?tty.KeyboardAndMouse.Button {
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
                    try self.menu.close()
                else
                    try self.menu.show(self.buffer);
            },
            else => {},
        }
    }
    return self.keyboard_buffer;
}

fn handleWindowResize(_: i32) callconv(.C) void {
    window_size = tty.Display.getWindowSize() catch unreachable;
    tty.Display.clearScreen() catch unreachable;
    if (should_render_in_center) {
        rows_pad = (@min(window_size.rows, std.math.maxInt(u8)) - g.DISPLAY_ROWS) / 2;
        cols_pad = (@min(window_size.cols, std.math.maxInt(u8)) - g.DISPLAY_COLS) / 2;
    }
}

fn writeBuffer(buffer: utf8.Buffer, writer: std.io.AnyWriter) !void {
    for (buffer.lines.items, rows_pad..) |line, i| {
        try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
        _ = try writer.write(line.bytes.items);
    }
}

pub fn runtime(self: *TtyRuntime) g.Runtime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .vtable = &.{
            .getCheat = getCheat,
            .addMenuItem = addMenuItem,
            .removeAllMenuItems = removeAllMenuItems,
            .currentMillis = currentMillis,
            .readPushedButtons = readPushedButtons,
            .clearDisplay = clearDisplay,
            .drawHorizontalBorderLine = drawHorizontalBorderLine,
            .drawMap = drawMap,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .drawText = drawText,
        },
    };
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
    const self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    return self.menu.addMenuItem(title, game_object, callback);
}

fn removeAllMenuItems(ptr: *anyopaque) void {
    const self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    self.menu.removeAllItems();
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    if (try self.reedKeyboardInput()) |key| {
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
            self.keyboard_buffer = null;
            return .{ .game_button = gbtn, .state = .pressed };
        } else {
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
    try tty.Display.clearScreen();
    // draw external border
    if (self.draw_border) {
        try self.wrapBufferInBorder();
    }
}

fn wrapBufferInBorder(self: *TtyRuntime) !void {
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

fn drawMap(ptr: *anyopaque, player: p.Point, map: g.Dungeon.Map) anyerror!void {
    var self: *TtyRuntime = @ptrCast(@alignCast(ptr));
    if (self.buffer.lines.items.len == 0) try self.wrapBufferInBorder();
    var itr = map.visited_places.keyIterator();
    while (itr.next()) |place| {
        try self.buffer.set('#', place.row, place.col);
    }
    for (map.visited_rooms.items, 0..) |room, i| {
        try self.drawBorder(room, ' ');
        if (map.room_with_entrance == i) {
            const entrance = room.center();
            try self.buffer.set('>', entrance.row, entrance.col);
        }
        if (map.room_with_exit == i) {
            const exit = room.center();
            try self.buffer.set('<', exit.row, exit.col);
        }
    }
    for (map.visited_doors.items) |door| {
        try self.buffer.set('+', door.row, door.col);
    }
    try self.buffer.set('@', player.row, player.col);
}

fn drawBorder(self: *TtyRuntime, region: p.Region, filler: u8) !void {
    const r = region.top_left.row;
    const c = region.top_left.col;

    var buf: [g.Dungeon.Map.cols * 3]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    _ = try writer.write("╔");
    if (region.cols > 2) try writer.writeBytesNTimes("═", region.cols - 2);
    _ = try writer.write("╗");
    try self.buffer.mergeLine(fbs.getWritten(), r, c);
    fbs.reset();

    if (region.rows > 2) {
        for (1..(region.rows - 1)) |l| {
            _ = try writer.write("║");
            if (region.cols > 2) try writer.writeByteNTimes(filler, region.cols - 2);
            _ = try writer.write("║");
            try self.buffer.mergeLine(fbs.getWritten(), r + l, c);
            fbs.reset();
        }
    }

    _ = try writer.write("╚");
    if (region.cols > 2) try writer.writeBytesNTimes("═", region.cols - 2);
    _ = try writer.write("╝");
    try self.buffer.mergeLine(fbs.getWritten(), region.bottomRightRow(), c);
    fbs.reset();
}

fn drawSprite(
    ptr: *anyopaque,
    screen: g.Screen,
    sprite: *const g.components.Sprite,
    position: *const g.components.Position,
    mode: g.Runtime.DrawingMode,
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
    mode: g.Runtime.DrawingMode,
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
