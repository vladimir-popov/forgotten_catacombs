const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const Self = @This();

pub const DrawingMode = enum { normal, inverted, transparent };

const VTable = struct {
    readPushedButtons: *const fn (context: *anyopaque) anyerror!?g.Button,
    clearDisplay: *const fn (context: *anyopaque) anyerror!void,
    drawScreenBorder: *const fn (context: *anyopaque) anyerror!void,
    drawHorizontalBorder: *const fn (context: *anyopaque) anyerror!void,
    drawDungeon: *const fn (
        context: *anyopaque,
        screen: g.Screen,
        dungeon: g.Dungeon,
    ) anyerror!void,
    drawSprite: *const fn (
        context: *anyopaque,
        screen: g.Screen,
        sprite: *const c.Sprite,
        position: *const c.Position,
        mode: DrawingMode,
    ) anyerror!void,
    drawText: *const fn (
        context: *anyopaque,
        text: []const u8,
        absolute_position: p.Point,
        mode: DrawingMode,
    ) anyerror!void,
    currentMillis: *const fn (context: *anyopaque) c_uint,
    getCheat: *const fn (context: *anyopaque) ?g.Cheat,
};

context: *anyopaque,
alloc: std.mem.Allocator,
vtable: *const VTable,

pub inline fn getCheat(self: Self) ?g.Cheat {
    return self.vtable.getCheat(self.context);
}

pub inline fn currentMillis(self: Self) c_uint {
    return self.vtable.currentMillis(self.context);
}

pub inline fn readPushedButtons(self: Self) !?g.Button {
    return try self.vtable.readPushedButtons(self.context);
}

pub inline fn clearDisplay(self: Self) !void {
    try self.vtable.clearDisplay(self.context);
}

pub inline fn drawScreenBorder(self: Self) !void {
    try self.vtable.drawScreenBorder(self.context);
}

pub inline fn drawHorizontalBorder(self: Self) !void {
    try self.vtable.drawHorizontalBorder(self.context);
}

pub inline fn drawDungeon(self: Self, screen: g.Screen, dungeon: g.Dungeon) !void {
    try self.vtable.drawDungeon(self.context, screen, dungeon);
}

pub inline fn drawSprite(
    self: Self,
    screen: g.Screen,
    sprite: *const c.Sprite,
    position: *const c.Position,
    mode: DrawingMode,
) !void {
    try self.vtable.drawSprite(self.context, screen, sprite, position, mode);
}

pub fn drawText(self: Self, text: []const u8, absolut_position: p.Point, mode: g.AnyRuntime.DrawingMode) !void {
    try self.vtable.drawText(self.context, text, absolut_position, mode);
}
