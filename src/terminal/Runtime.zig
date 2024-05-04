const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");
const utf8 = @import("utf8");
const Render = @import("Render.zig");

const Self = @This();

alloc: std.mem.Allocator,
arena: *std.heap.ArenaAllocator,
rand: std.Random,
buffer: utf8.Buffer,
termios: std.c.termios,
// the last read button through readButton function.
// it is used as a buffer to check ESC outside the readButton function
pressed_button: ?tty.Keyboard.Button = null,

pub fn init(alloc: std.mem.Allocator, rand: std.Random, arena: *std.heap.ArenaAllocator) !Self {
    const instance = Self{
        .alloc = alloc,
        .arena = arena,
        .rand = rand,
        .buffer = utf8.Buffer.init(arena.allocator()),
        .termios = tty.Display.enterRawMode(),
    };
    tty.Display.hideCursor();
    return instance;
}

pub fn deinit(self: Self) void {
    tty.Display.exitFromRawMode(self.termios);
    tty.Display.showCursor();
    _ = self.arena.reset(.free_all);
}

/// Run the main loop for game, which should be
/// the *gm.ForgottenCatacomb.Game
/// or *DungeonsGenerator.Game
pub fn run(self: *Self, game: anytype) !void {
    tty.Display.clearScreen();
    while (!self.isExit()) {
        try game.tick();
        try self.drawBuffer(1, 1);
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

// row & col begin from 1
fn drawBuffer(self: Self, rows_pad: u8, cols_pad: u8) !void {
    try self.writeBuffer(tty.Display.writer, rows_pad, cols_pad);
}

fn writeBuffer(self: Self, writer: std.io.AnyWriter, rows_pad: u8, cols_pad: u8) !void {
    for (self.buffer.lines.items, rows_pad..) |line, i| {
        try tty.Text.writeSetCursorPosition(writer, @intCast(i), cols_pad);
        _ = try writer.write(line.bytes.items);
    }
}

fn resetBuffer(self: *Self) void {
    _ = self.arena.reset(.retain_capacity);
    self.buffer = utf8.Buffer.init(self.arena.allocator());
}

pub fn any(self: *Self) gm.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .rand = self.rand,
        .vtable = .{
            .readButton = readButton,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
        },
    };
}

fn readButton(ptr: *anyopaque) anyerror!?gm.Button.Type {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.pressed_button = tty.Keyboard.readPressedButton();
    if (self.pressed_button) |key| {
        switch (key) {
            .char => switch (key.char.char) {
                ' ' => return gm.Button.A,
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

fn drawDungeon(ptr: *anyopaque, dungeon: *const gm.Dungeon) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try Render.drawDungeon(self.arena.allocator(), &self.buffer, dungeon, .{ .r = 1, .c = 1, .rows = dungeon.rows, .cols = dungeon.cols });
}

fn drawSprite(ptr: *anyopaque, sprite: *const gm.Sprite, row: u8, col: u8) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try self.buffer.mergeLine(sprite.letter, row - 1, col - 1);
}
