const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.runtime);

const Runtime = @This();

pub const DrawingMode = enum { normal, inverted };
pub const TextAlign = enum { center, left, right };
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
    drawSprite: *const fn (
        context: *anyopaque,
        codepoint: g.Codepoint,
        position_on_display: p.Point,
        mode: DrawingMode,
    ) anyerror!void,
    drawText: *const fn (
        context: *anyopaque,
        text: []const u8,
        position_on_display: p.Point,
        mode: DrawingMode,
    ) anyerror!void,
    currentMillis: *const fn (context: *anyopaque) c_uint,
    isDevMode: *const fn (context: *anyopaque) bool,
    popCheat: *const fn (context: *anyopaque) ?g.Cheat,
};

context: *anyopaque,
vtable: *const VTable,

pub inline fn isDevMode(self: Runtime) bool {
    return self.vtable.isDevMode(self.context);
}

pub inline fn popCheat(self: Runtime) ?g.Cheat {
    return self.vtable.popCheat(self.context);
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

pub fn drawSprite(self: Runtime, codepoint: u21, position_on_display: p.Point, mode: DrawingMode) !void {
    try self.vtable.drawSprite(self.context, codepoint, position_on_display, mode);
}

pub fn drawText(self: Runtime, text: []const u8, position_on_display: p.Point, mode: DrawingMode) !void {
    try self.vtable.drawText(self.context, text, position_on_display, mode);
}
