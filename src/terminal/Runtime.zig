const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game");
const cmp = game.components;
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
    tty.Display.exitFromRawMode();
    tty.Display.showCursor();
    _ = self.arena.reset(.free_all);
}

/// Run the main loop for game, which should be
/// the *gm.ForgottenCatacomb.Universe
/// or *DungeonsGenerator.Universe
pub fn run(self: *Self, universe: anytype) !void {
    tty.Display.clearScreen();
    while (!self.isExit()) {
        try universe.tick();
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

pub fn any(self: *Self) game.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .rand = self.rand,
        .vtable = .{
            .readButton = readButton,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .currentMillis = currentMillis,
        },
    };
}

fn currentMillis(_: *anyopaque) i64 {
    return std.time.milliTimestamp();
}

fn readButton(ptr: *anyopaque) anyerror!game.Button.Type {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.pressed_button = tty.Keyboard.readPressedButton();
    if (self.pressed_button) |key| {
        switch (key) {
            .char => switch (key.char.char) {
                ' ' => return game.Button.A,
                'f' => return game.Button.B,
                'd' => return game.Button.A,
                'h' => return game.Button.Left,
                'j' => return game.Button.Down,
                'k' => return game.Button.Up,
                'l' => return game.Button.Right,
                else => return game.Button.None,
            },
            else => return game.Button.None,
        }
    }
    return game.Button.None;
}

fn drawDungeon(ptr: *anyopaque, screen: *const game.Screen, dungeon: *const game.Dungeon) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    try Render.drawDungeon(
        self.arena.allocator(),
        &self.buffer,
        dungeon,
        screen.region,
    );
}

fn drawSprite(
    ptr: *anyopaque,
    screen: *const game.Screen,
    sprite: *const cmp.Sprite,
    position: *const cmp.Position,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        var self: *Self = @ptrCast(@alignCast(ptr));
        const r = position.point.row - screen.region.top_left.row;
        const c = position.point.col - screen.region.top_left.col;
        try self.buffer.mergeLine(sprite.letter, r, c);
    }
}
