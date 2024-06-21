const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

pub const DOUBLE_PRESS_DELAY_MS = 150;
pub const HOLD_DELAY_MS = 500;

const Self = @This();

pub const Buttons = struct {
    pub const Code = c_int;

    pub const State = enum { pressed, hold, double_pressed };

    code: Code,
    state: State,

    pub const Left: Code = (1 << 0);
    pub const Right: Code = (1 << 1);
    pub const Up: Code = (1 << 2);
    pub const Down: Code = (1 << 3);
    pub const B: Code = (1 << 4);
    pub const A: Code = (1 << 5);

    pub inline fn isMove(btn: Code) bool {
        return (Up | Down | Left | Right) & btn > 0;
    }

    pub inline fn toDirection(btn: Buttons) ?p.Direction {
        return if (btn.code & Buttons.Up > 0)
            p.Direction.up
        else if (btn.code & Buttons.Down > 0)
            p.Direction.down
        else if (btn.code & Buttons.Left > 0)
            p.Direction.left
        else if (btn.code & Buttons.Right > 0)
            p.Direction.right
        else
            null;
    }
};

const VTable = struct {
    readButtons: *const fn (context: *anyopaque) anyerror!?Buttons,
    drawUI: *const fn (context: *anyopaque) anyerror!void,
    drawDungeon: *const fn (
        context: *anyopaque,
        screen: *const game.Screen,
        dungeon: *const game.Dungeon,
    ) anyerror!void,
    drawSprite: *const fn (
        context: *anyopaque,
        screen: *const game.Screen,
        sprite: *const game.Sprite,
    ) anyerror!void,
    drawLabel: *const fn (
        context: *anyopaque,
        label: []const u8,
        absolute_position: p.Point,
    ) anyerror!void,
    currentMillis: *const fn (context: *anyopaque) i64,
};

context: *anyopaque,
alloc: std.mem.Allocator,
rand: std.Random,
vtable: *const VTable,

pub inline fn currentMillis(self: Self) i64 {
    return self.vtable.currentMillis(self.context);
}

pub inline fn readButtons(self: Self) !?Buttons {
    return try self.vtable.readButtons(self.context);
}

pub inline fn drawUI(self: Self) !void {
    try self.vtable.drawUI(self.context);
}

pub inline fn drawDungeon(self: Self, screen: *const game.Screen, dungeon: *const game.Dungeon) !void {
    try self.vtable.drawDungeon(self.context, screen, dungeon);
}

pub inline fn drawSprite(
    self: Self,
    screen: *const game.Screen,
    sprite: *const game.Sprite,
) !void {
    try self.vtable.drawSprite(self.context, screen, sprite);
}

pub inline fn drawLabel(self: Self, label: []const u8, absolute_position: p.Point) !void {
    try self.vtable.drawLabel(self.context, label, absolute_position);
}
