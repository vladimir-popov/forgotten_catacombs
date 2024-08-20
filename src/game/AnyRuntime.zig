const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Self = @This();

pub const DrawingMode = enum { normal, inverted, transparent };

pub const TextAlign = enum { center, left, right };

const VTable = struct {
    readPushedButtons: *const fn (context: *anyopaque) anyerror!?game.Buttons,
    clearDisplay: *const fn (context: *anyopaque) anyerror!void,
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
        position: *const game.Position,
        mode: DrawingMode,
    ) anyerror!void,
    drawText: *const fn (
        context: *anyopaque,
        text: []const u8,
        absolute_position: p.Point,
        mode: DrawingMode,
    ) anyerror!void,
    currentMillis: *const fn (context: *anyopaque) c_uint,
};

context: *anyopaque,
alloc: std.mem.Allocator,
rand: std.Random,
vtable: *const VTable,

pub inline fn currentMillis(self: Self) c_uint {
    return self.vtable.currentMillis(self.context);
}

pub inline fn readPushedButtons(self: Self) !?game.Buttons {
    return try self.vtable.readPushedButtons(self.context);
}

pub inline fn clearDisplay(self: Self) !void {
    try self.vtable.clearDisplay(self.context);
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
    position: *const game.Position,
    mode: DrawingMode,
) !void {
    try self.vtable.drawSprite(self.context, screen, sprite, position, mode);
}

pub fn drawText(
    self: Self,
    comptime len: u8,
    text: []const u8,
    absolut_position: p.Point,
    mode: game.AnyRuntime.DrawingMode,
    aln: TextAlign,
) !void {
    var buf: [len]u8 = undefined;
    inline for (0..len) |i| buf[i] = ' ';
    const l = @min(len, text.len);
    switch (aln) {
        .left => std.mem.copyForwards(u8, &buf, text[0..l]),
        .center => std.mem.copyForwards(u8, buf[(len - l) / 2 ..], text[0..l]),
        .right => std.mem.copyForwards(u8, buf[(len - l)..], text[0..l]),
    }
    try self.vtable.drawText(self.context, &buf, absolut_position, mode);
}
