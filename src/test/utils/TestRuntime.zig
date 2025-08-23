const std = @import("std");
const g = @import("game");
const p = g.primitives;
const terminal = @import("terminal");

const Frame = @import("Frame.zig");
const Menu = terminal.TtyRuntime.Menu;

const Self = @This();

alloc: std.mem.Allocator,
working_dir: std.fs.Dir,
menu: Menu(g.DISPLAY_ROWS, g.DISPLAY_COLS),
display: Frame = .empty,
last_frame: Frame = .empty,
pushed_buttons: std.ArrayListUnmanaged(?g.Button) = .empty,

is_dev_mode: bool = false,
cheat: ?g.Cheat = null,

pub fn init(alloc: std.mem.Allocator, working_dir: std.fs.Dir) !Self {
    return .{
        .alloc = alloc,
        .working_dir = working_dir,
        .menu = try Menu(g.DISPLAY_ROWS, g.DISPLAY_COLS).init(alloc),
    };
}

pub fn deinit(self: *Self) void {
    self.menu.deinit();
    self.pushed_buttons.deinit(self.alloc);
}

pub fn runtime(self: *Self) g.Runtime {
    return .{
        .context = self,
        .vtable = &.{
            .isDevMode = isDevMode,
            .popCheat = popCheat,
            .addMenuItem = addMenuItem,
            .removeAllMenuItems = removeAllMenuItems,
            .currentMillis = currentMillis,
            .readPushedButtons = readPushedButtons,
            .clearDisplay = clearDisplay,
            .drawSprite = drawSprite,
            .openFile = openFile,
            .closeFile = closeFile,
            .readFromFile = readFromFile,
            .writeToFile = writeToFile,
            .isFileExists = isFileExists,
            .deleteFileIfExists = deleteFileIfExists,
        },
    };
}

fn currentMillis(_: *anyopaque) c_uint {
    return @truncate(@as(u64, @intCast(std.time.milliTimestamp())));
}

fn addMenuItem(
    ptr: *anyopaque,
    title: []const u8,
    game_object: *anyopaque,
    callback: g.Runtime.MenuItemCallback,
) ?*anyopaque {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.menu.addMenuItem(title, game_object, callback);
}

fn removeAllMenuItems(ptr: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.menu.removeAllItems();
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return if (self.pushed_buttons.pop()) |maybe_button| maybe_button else null;
}

fn isDevMode(ptr: *anyopaque) bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.is_dev_mode;
}

fn popCheat(ptr: *anyopaque) ?g.Cheat {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.cheat;
}

fn clearDisplay(ptr: *anyopaque) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.display = .empty;
}

fn drawSprite(ptr: *anyopaque, codepoint: u21, position_on_display: p.Point, mode: g.DrawingMode) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const i = position_on_display.row - 1;
    const j = position_on_display.col - 1;
    self.last_frame.sprites[i][j] = .{ .codepoint = codepoint, .mode = mode };
}

fn openFile(ptr: *anyopaque, file_path: []const u8, mode: g.Runtime.FileMode) anyerror!*anyopaque {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file = try self.alloc.create(std.fs.File);
    switch (mode) {
        .read => file.* = try self.working_dir.openFile(file_path, .{ .mode = std.fs.File.OpenMode.read_only }),
        .write => file.* = try self.working_dir.createFile(file_path, .{}),
    }
    return file;
}

fn closeFile(ptr: *anyopaque, file_ptr: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
    file.close();
    self.alloc.destroy(file);
}

fn readFromFile(_: *anyopaque, file_ptr: *anyopaque, buffer: []u8) anyerror!usize {
    const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
    return try file.read(buffer);
}

fn writeToFile(_: *anyopaque, file_ptr: *anyopaque, bytes: []const u8) anyerror!usize {
    const file: *std.fs.File = @ptrCast(@alignCast(file_ptr));
    return try file.write(bytes);
}

fn isFileExists(ptr: *anyopaque, file_path: []const u8) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.working_dir.access(file_path, .{})) |_| {
        return true;
    } else |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    }
}

fn deleteFileIfExists(ptr: *anyopaque, file_path: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.working_dir.deleteFile(file_path) catch |err| {
        switch (err) {
            error.FileNotFound => {},
            else => return err,
        }
    };
}
