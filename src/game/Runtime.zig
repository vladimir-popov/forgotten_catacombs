const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.runtime);

const Runtime = @This();

pub const DrawingMode = enum { normal, inverted };
pub const TextAlign = enum { center, left, right };
pub const MenuItemCallback = *const fn (userdata: ?*anyopaque) callconv(.c) void;
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
    currentMillis: *const fn (context: *anyopaque) c_uint,
    isDevMode: *const fn (context: *anyopaque) bool,
    popCheat: *const fn (context: *anyopaque) ?g.Cheat,
    // --------- FS operations ---------
    // All paths should be relative to a directory with save files
    openFile: *const fn (context: *anyopaque, file_path: []const u8, mode: FileMode) anyerror!File,
    closeFile: *const fn (context: *anyopaque, file: File) void,
    readFromFile: *const fn (context: *anyopaque, file: File, buffer: []u8) anyerror!usize,
    writeToFile: *const fn (context: *anyopaque, file: File, bytes: []const u8) anyerror!usize,
    isFileExists: *const fn (context: *anyopaque, path: []const u8) anyerror!bool,
    deleteFileIfExists: *const fn (context: *anyopaque, path: []const u8) anyerror!void,
    //  ----------------------------------
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

pub inline fn openFile(self: Runtime, file_path: []const u8, mode: FileMode) anyerror!File {
    return try self.vtable.openFile(self.context, file_path, mode);
}

pub inline fn closeFile(self: Runtime, file: File) void {
    self.vtable.closeFile(self.context, file);
}

pub fn isFileExists(self: Runtime, path: []const u8) anyerror!bool {
    return try self.vtable.isFileExists(self.context, path);
}

pub fn deleteFileIfExists(self: Runtime, path: []const u8) anyerror!void {
    try self.vtable.deleteFileIfExists(self.context, path);
}

pub const FileReader = struct {
    runtime: Runtime,
    file: File,
    interface: std.io.Reader,

    pub fn init(runtime: Runtime, file: File, buffer: []u8) FileReader {
        return .{
            .runtime = runtime,
            .file = file,
            .interface = .{
                .buffer = buffer,
                .seek = 0,
                .end = buffer.len,
                .vtable = &.{ .stream = FileReader.stream },
            },
        };
    }

    pub fn stream(io_r: *std.io.Reader, io_w: *std.io.Writer, limit: std.io.Limit) std.io.Reader.StreamError!usize {
        _ = limit;
        const self: *FileReader = @fieldParentPtr("interface", io_r);
        var buffer: [128]u8 = undefined;
        const len = self.runtime.vtable.readFromFile(self.runtime.context, self.file, &buffer) catch |err| {
            log.err("Error on reading from the file {any}: {any}", .{self.file, err});
            return error.ReadFailed;
        };
        try io_w.writeAll(buffer[0..len]);
        return len;
    }

    pub fn close(self: FileReader) void {
        self.runtime.closeFile(self.file);
    }
};

pub fn fileReader(self: Runtime, file_path: []const u8, buffer: []u8) !FileReader {
    return .init(self, try self.openFile(file_path, .read), buffer);
}

pub const FileWriter = struct {
    runtime: Runtime,
    file: File,
    interface: std.io.Writer,

    pub fn init(runtime: Runtime, file: File, buffer: []u8) FileWriter {
        return .{
            .runtime = runtime,
            .file = file,
            .interface = .{ .buffer = buffer, .vtable = &.{ .drain = FileWriter.drain } },
        };
    }

    pub fn close(self: FileWriter) void {
        self.runtime.closeFile(self.file);
    }

    pub fn drain(io_w: *std.io.Writer, data: []const []const u8, splat: usize) std.io.Writer.Error!usize {
        _ = splat;
        const self: *FileWriter = @fieldParentPtr("interface", io_w);
        const len = self.runtime.vtable.writeToFile(self.runtime.context, self.file, data[0]) catch |err| {
            log.err("Error on writing to the file {any}: {any}", .{ self.file, err });
            return error.WriteFailed;
        };
        if (len < data[0].len) {
            log.err("No space left in the file {any}", .{self.file});
            return error.WriteFailed;
        }
        return len;
    }
};

pub fn fileWriter(self: Runtime, file_path: []const u8, buffer: []u8) !FileWriter {
    return .init(self, try self.openFile(file_path, .write), buffer);
}
