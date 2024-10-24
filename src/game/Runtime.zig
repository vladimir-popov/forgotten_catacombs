const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.runtime);

const Runtime = @This();

pub const DrawingMode = enum { normal, inverted, transparent };

pub const MenuItemCallback = *const fn (userdata: ?*anyopaque) callconv(.C) void;

const VTable = struct {
    readPushedButtons: *const fn (context: *anyopaque) anyerror!?g.Button,
    addMenuItem: *const fn (
        context: *anyopaque,
        title: []const u8,
        game_object: *anyopaque,
        callback: MenuItemCallback,
    ) ?*anyopaque,
    removeAllMenuItems: *const fn (context: *anyopaque) void,
    clearDisplay: *const fn (context: *anyopaque) anyerror!void,
    drawHorizontalBorderLine: *const fn (context: *anyopaque, row: u8, length: u8) anyerror!void,
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

pub inline fn getCheat(self: Runtime) ?g.Cheat {
    return self.vtable.getCheat(self.context);
}

pub inline fn currentMillis(self: Runtime) c_uint {
    return self.vtable.currentMillis(self.context);
}

pub inline fn addMenuItem(
    self: Runtime,
    title: []const u8,
    game_object: *anyopaque,
    callback: MenuItemCallback,
) ?*anyopaque {
    return self.vtable.addMenuItem(self.context, title, game_object, callback);
}

pub inline fn removeAllMenuItems(self: Runtime) void {
    self.vtable.removeAllMenuItems(self.context);
}

pub inline fn readPushedButtons(self: Runtime) !?g.Button {
    const btn = try self.vtable.readPushedButtons(self.context);
    if (btn) |b| log.debug("Pressed button {s}", .{@tagName(b.game_button)});
    return btn;
}

pub inline fn clearDisplay(self: Runtime) !void {
    try self.vtable.clearDisplay(self.context);
}

pub inline fn drawHorizontalBorderLine(self: Runtime, row: u8, length: u8) !void {
    try self.vtable.drawHorizontalBorderLine(self.context, row, length);
}

pub inline fn drawDungeon(self: Runtime, screen: g.Screen, dungeon: g.Dungeon) !void {
    try self.vtable.drawDungeon(self.context, screen, dungeon);
}

pub fn drawMap(self: Runtime, player: p.Point, map: g.Dungeon.Map) !void {
    try self.vtable.drawMap(self.context, player, map);
}

pub inline fn drawSprite(
    self: Runtime,
    screen: g.Screen,
    sprite: *const c.Sprite,
    position: *const c.Position,
    mode: DrawingMode,
) !void {
    try self.vtable.drawSprite(self.context, screen, sprite, position, mode);
}

pub fn drawText(self: Runtime, text: []const u8, absolut_position: p.Point, mode: g.Runtime.DrawingMode) !void {
    try self.vtable.drawText(self.context, text, absolut_position, mode);
}
