//! This is a kind of the fat pointer similar to the `std.mem.Allocator`.
//! It means, the `Render` can be always passed by value.
const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.runtime);

const Self = @This();

pub const DrawingMode = enum { normal, inverted };
pub const TextAlign = enum { center, left, right };
pub const MenuItemCallback = *const fn (userdata: ?*anyopaque) callconv(.c) void;
pub const OpaqueFile = *anyopaque;
pub const FileMode = enum { read, write };

const VTable = struct {
    readPushedButtons: *const fn (context: *anyopaque) anyerror!?g.Button,
    cleanInputBuffer: *const fn (context: *anyopaque) anyerror!void,
    addMenuItem: *const fn (
        context: *anyopaque,
        title: [:0]const u8,
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
    currentMillis: *const fn (context: *anyopaque) u64,
    isDevMode: *const fn (context: *anyopaque) bool,
    popCheat: *const fn (context: *anyopaque) ?g.Cheat,
    // --------- FS operations ---------
    // All paths should be relative to a directory with save files
    openFile: *const fn (context: *anyopaque, file_path: [:0]const u8, mode: FileMode, buffer: []u8) anyerror!OpaqueFile,
    closeFile: *const fn (context: *anyopaque, file: OpaqueFile) void,
    readFile: *const fn (context: *anyopaque, file: OpaqueFile) *std.Io.Reader,
    writeToFile: *const fn (context: *anyopaque, file: OpaqueFile) *std.Io.Writer,
    isFileExists: *const fn (context: *anyopaque, path: [:0]const u8) anyerror!bool,
    deleteFileIfExists: *const fn (context: *anyopaque, path: [:0]const u8) anyerror!void,
    //  ----------------------------------
};

context: *anyopaque,
vtable: *const VTable,

pub inline fn isDevMode(self: *const Self) bool {
    return self.vtable.isDevMode(self.context);
}

pub inline fn popCheat(self: *const Self) ?g.Cheat {
    return self.vtable.popCheat(self.context);
}

pub inline fn currentMillis(self: *const Self) u64 {
    return self.vtable.currentMillis(self.context);
}

pub inline fn addMenuItem(
    self: *const Self,
    title: [:0]const u8,
    game_object: *anyopaque,
    callback: MenuItemCallback,
) ?*anyopaque {
    return self.vtable.addMenuItem(self.context, title, game_object, callback);
}

pub inline fn removeAllMenuItems(self: *const Self) void {
    self.vtable.removeAllMenuItems(self.context);
}

pub fn readPushedButtons(self: *const Self) !?g.Button {
    const btn = try self.vtable.readPushedButtons(self.context);
    if (btn) |b| log.debug("Pressed button {s}", .{@tagName(b.game_button)});
    return btn;
}

pub fn cleanInputBuffer(self: *const Self) !void {
    try self.vtable.cleanInputBuffer(self.context);
}

pub fn clearDisplay(self: *const Self) !void {
    try self.vtable.clearDisplay(self.context);
}

pub fn drawSprite(self: *const Self, codepoint: u21, position_on_display: p.Point, mode: DrawingMode) !void {
    try self.vtable.drawSprite(self.context, codepoint, position_on_display, mode);
}

pub fn openFile(self: *const Self, file_path: [:0]const u8, mode: FileMode, buffer: []u8) anyerror!OpaqueFile {
    return self.vtable.openFile(self.context, file_path, mode, buffer) catch |err| {
        log.err("Error {t} on opening to {t} file {s}", .{ err, mode, file_path });
        return err;
    };
}

pub fn closeFile(self: *const Self, file: OpaqueFile) void {
    self.vtable.closeFile(self.context, file);
}

pub fn readFile(self: *const Self, file: OpaqueFile) *std.Io.Reader {
    return self.vtable.readFile(self.context, file);
}

pub fn writeToFile(self: *const Self, file: OpaqueFile) *std.Io.Writer {
    return self.vtable.writeToFile(self.context, file);
}

pub fn isFileExists(self: *const Self, path: [:0]const u8) anyerror!bool {
    return try self.vtable.isFileExists(self.context, path);
}

pub fn deleteFileIfExists(self: *const Self, path: [:0]const u8) anyerror!void {
    try self.vtable.deleteFileIfExists(self.context, path);
}
