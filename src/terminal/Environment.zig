const std = @import("std");
const game = @import("game");
const tty = @import("tty.zig");
const utf8 = @import("utf8");

const Self = @This();

termios: std.c.termios,
buffer: utf8.Buffer,
rows: u8,
cols: u8,

pub fn init(rows: u8, cols: u8, alloc: std.mem.Allocator) !Self {
    return .{
        .termios = tty.Display.enterRawMode(),
        .buffer = utf8.Buffer.init(alloc),
        .rows = rows,
        .cols = cols,
    };
}

pub fn deinit(self: Self) void {
    tty.Display.exitFromRawMode(self.termios);
    self.buffer.deinit();
}

pub fn runtime(self: *Self) game.Runtime(Self) {
    return .{
        .environment = self,
        .rows = self.rows,
        .cols = self.cols,
        .vtable = .{
            .drawSprite = drawSprite,
            .readButton = readButton,
        },
    };
}

fn readButton(_: *Self) anyerror!?game.Button.Type {
    const key = tty.Keyboard.readPressedKey();
    switch (key) {
        .char => switch (key.char.char) {
            'f' => return game.Button.B,
            'd' => return game.Button.A,
            'h' => return game.Button.Left,
            'j' => return game.Button.Down,
            'k' => return game.Button.Up,
            'l' => return game.Button.Right,
            else => return null,
        },
        else => return null,
    }
}

fn drawSprite(self: *Self, sprite: *const game.Sprite, row: u8, col: u8) anyerror!void {
    try self.buffer.mergeLine(sprite.letter, row, col);
}
