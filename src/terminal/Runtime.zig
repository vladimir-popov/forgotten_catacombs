const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");
const utf8 = @import("utf8");

const Self = @This();

arena: *std.heap.ArenaAllocator,
buffer: utf8.Buffer,
termios: std.c.termios,
rows: u8,
cols: u8,
pressed_button: ?tty.Keyboard.Button = null,

pub fn init(arena: *std.heap.ArenaAllocator, rows: u8, cols: u8) !Self {
    const instance = Self{
        .arena = arena,
        .buffer = utf8.Buffer.init(arena.allocator()),
        .termios = tty.Display.enterRawMode(),
        .rows = rows,
        .cols = cols,
    };
    tty.Display.hideCursor();
    return instance;
}

pub fn deinit(self: Self) void {
    tty.Display.exitFromRawMode(self.termios);
    _ = self.arena.reset(.free_all);
}

// row & col begin from 1
pub fn drawBuffer(self: Self, row: u8, col: u8) !void {
    try self.writeBuffer(tty.Display.writer, row, col);
}

fn writeBuffer(self: Self, writer: std.io.AnyWriter, row: u8, col: u8) !void {
    for (self.buffer.lines.items, row..) |line, i| {
        try tty.Text.writeSetCursorPosition(writer, @intCast(i), col);
        _ = try writer.write(line.bytes.items);
    }
}

pub fn resetBuffer(self: *Self) void {
    _ = self.arena.reset(.retain_capacity);
    self.buffer = utf8.Buffer.init(self.arena.allocator());
}

pub fn run(self: *Self, game: *gm.ForgottenCatacomb.Game) !void {
    tty.Display.clearScreen();
    while (!self.isExit()) {
        try game.tick();
        try self.drawBuffer(0, 0);
        self.resetBuffer();
    }
}

fn isExit(self: Self) bool {
    if (self.pressed_button) |btn| {
        switch (btn) {
            .control => return btn.control == tty.Keyboard.ControlButton.ESC,
            else => return false,
        }
    } else {
        return false;
    }
}

pub fn any(self: *Self) gm.AnyRuntime {
    return .{
        .context = self,
        .vtable = .{
            .drawSprite = drawSprite,
            .readButton = readButton,
        },
    };
}

fn readButton(ptr: *anyopaque) anyerror!?gm.Button.Type {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.pressed_button = tty.Keyboard.readPressedButton();
    if (self.pressed_button) |key| {
        switch (key) {
            .char => switch (key.char.char) {
                'f' => return gm.Button.B,
                'd' => return gm.Button.A,
                'h' => return gm.Button.Left,
                'j' => return gm.Button.Down,
                'k' => return gm.Button.Up,
                'l' => return gm.Button.Right,
                else => return null,
            },
            else => return null,
        }
    }
    return null;
}

fn drawSprite(ptr: *anyopaque, sprite: *const gm.Sprite, row: u8, col: u8) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.buffer.mergeLine(sprite.letter, row, col);
}
