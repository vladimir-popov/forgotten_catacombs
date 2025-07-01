const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.runtime);

const Runtime = @This();

pub const DrawingMode = enum { normal, inverted };
pub const TextAlign = enum { center, left, right };
pub const MenuItemCallback = *const fn (userdata: ?*anyopaque) callconv(.C) void;
pub const File = *anyopaque;
pub const FileMode = enum { read, write };

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
    openFile: *const fn (context: *anyopaque, file_path: []const u8, mode: FileMode) anyerror!File,
    closeFile: *const fn (context: *anyopaque, file: File) void,
    readFile: *const fn (context: *anyopaque, file: File, buffer: []u8) anyerror!usize,
    writeFile: *const fn (context: *anyopaque, file: File, bytes: []const u8) anyerror!usize,
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

pub inline fn drawSprite(self: Runtime, codepoint: u21, position_on_display: p.Point, mode: DrawingMode) !void {
    try self.vtable.drawSprite(self.context, codepoint, position_on_display, mode);
}

pub inline fn drawText(self: Runtime, text: []const u8, position_on_display: p.Point, mode: DrawingMode) !void {
    try self.vtable.drawText(self.context, text, position_on_display, mode);
}

pub inline fn openFile(self: Runtime, file_path: []const u8, mode: FileMode) anyerror!File {
    return try self.vtable.openFile(self.context, file_path, mode);
}

pub inline fn closeFile(self: Runtime, file: File) void {
    self.vtable.closeFile(self.context, file);
}

pub inline fn readFile(self: Runtime, file: File, buffer: []u8) anyerror!usize {
    return try self.vtable.readFile(self.context, file, buffer);
}

pub inline fn writeFile(self: Runtime, file: File, bytes: []const u8) anyerror!usize {
    return try self.vtable.writeFile(self.context, file, bytes);
}

pub const FileReader = struct {
    pub const Error = anyerror;
    pub const Reader = std.io.Reader(FileReader, Error, read);

    runtime: Runtime,
    file: File,

    pub fn read(self: FileReader, buffer: []u8) Error!usize {
        return try self.runtime.readFile(self.file, buffer);
    }

    pub fn deinit(self: FileReader) void {
        self.runtime.closeFile(self.file);
    }

    pub fn reader(self: FileReader) Reader {
        return .{ .context = self };
    }
};

pub fn fileReader(self: Runtime, file_path: []const u8) !FileReader {
    return .{ .runtime = self, .file = try self.openFile(file_path, .read) };
}

pub const FileWriter = struct {
    pub const Error = anyerror;
    pub const Writer = std.io.Writer(FileWriter, Error, write);

    runtime: Runtime,
    file: File,

    pub fn deinit(self: FileWriter) void {
        self.runtime.closeFile(self.file);
    }

    pub fn write(self: FileWriter, bytes: []const u8) Error!usize {
        return try self.runtime.writeFile(self.file, bytes);
    }

    pub fn writeAll(self: FileWriter, bytes: []const u8) Error!void {
        const len = try self.write(bytes);
        if (len < bytes.len)
            return error.NoSpaceLeft;
    }

    pub fn writer(self: FileWriter) Writer {
        return .{ .context = self };
    }
};

pub fn fileWriter(self: Runtime, file_path: []const u8) !FileWriter {
    return .{ .runtime = self, .file = try self.openFile(file_path, .write) };
}
