const std = @import("std");
const api = @import("api.zig");
const io = @import("io.zig");
const g = @import("game");
const c = g.components;
const p = g.primitives;

const Allocator = @import("Allocator.zig");
const LastButton = @import("LastButton.zig");

const log = std.log.scoped(.playdate_runtime);

const Self = @This();

// This is a global var because the
// serialMessageCallback doesn't receive custom data
var cheat: ?g.Cheat = null;

// The path to the dir with save files
const save_dir: [:0]const u8 = "save";

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
bitmap_table: *api.LCDBitmapTable,
last_button: *LastButton,
is_dev_mode: bool = false,

pub fn init(playdate: *api.PlaydateAPI) !Self {
    const err: ?*[*c]const u8 = null;

    const bitmap_table: *api.LCDBitmapTable = playdate.graphics.loadBitmapTable("sprites", err) orelse {
        const reason = err orelse "unknown reason";
        std.debug.panic("Bitmap table was not created because of {s}", .{reason});
    };
    errdefer _ = playdate.system.realloc(bitmap_table, 0);

    if (err) |err_msg| {
        std.debug.panic("Error on loading image to the bitmap table: {s}", .{err_msg});
    }

    const alloc = Allocator.allocator(playdate);
    const last_button = try alloc.create(LastButton);
    last_button.* = .reset;
    errdefer alloc.destroy(last_button);

    playdate.system.setSerialMessageCallback(serialMessageCallback);
    playdate.system.setButtonCallback(LastButton.handleEvent, last_button, 1);
    if (playdate.file.mkdir(save_dir.ptr) < 0)
        std.debug.panic("Error on creating dir {s}", .{save_dir});

    return .{
        .playdate = playdate,
        .alloc = alloc,
        .bitmap_table = bitmap_table,
        .last_button = last_button,
    };
}

pub fn deinit(self: *Self) void {
    self.playdate.realloc(0, self.bitmap_table);
    self.playdate.realloc(0, self.last_button);
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
            .readFile = readFile,
            .writeToFile = writeToFile,
            .isFileExists = isFileExists,
            .deleteFileIfExists = deleteFileIfExists,
        },
    };
}

// ======== Private methods: ==============

fn isDevMode(ptr: *anyopaque) bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.is_dev_mode;
}

fn currentMillis(ptr: *anyopaque) c_uint {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.playdate.system.getCurrentTimeMilliseconds();
}

fn addMenuItem(
    ptr: *anyopaque,
    title: []const u8,
    game_object: *anyopaque,
    callback: g.Runtime.MenuItemCallback,
) ?*anyopaque {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.playdate.system.addMenuItem(title.ptr, callback, game_object).?;
}

fn removeAllMenuItems(ptr: *anyopaque) void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.playdate.system.removeAllMenuItems();
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
    const self: *Self = @ptrCast(@alignCast(ptr));

    if (self.playdate.system.isCrankDocked() == 0) {
        const change = self.playdate.system.getCrankChange();
        const angle = self.playdate.system.getCrankAngle();
        if (change > 2.0 and angle > 170.0 and angle < 190.0) {
            cheat = .move_player_to_ladder_down;
        }
        if (change < -2.0 and (angle > 350.0 or angle < 10.0)) {
            cheat = .move_player_to_ladder_up;
        }
    }

    return self.last_button.pop(currentMillis(ptr));
}

fn clearDisplay(ptr: *anyopaque) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorBlack));
}

fn drawSprite(ptr: *anyopaque, codepoint: g.Codepoint, position_on_display: p.Point, mode: g.DrawingMode) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    const x = @as(c_int, position_on_display.col - 1) * g.SPRITE_WIDTH;
    const y = @as(c_int, position_on_display.row - 1) * g.SPRITE_HEIGHT;
    if (mode == .inverted)
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeInverted)
    else
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    self.playdate.graphics.drawBitmap(self.getBitmap(codepoint), x, y, .BitmapUnflipped);
}

fn getBitmap(self: Self, codepoint: g.Codepoint) *api.LCDBitmap {
    const idx = getCodepointIdx(codepoint);
    return self.playdate.graphics.getTableBitmap(self.bitmap_table, idx) orelse {
        std.debug.panic("Wrong index {d} for codepoint {d}", .{ idx, codepoint });
    };
}

fn getCodepointIdx(codepoint: g.Codepoint) c_int {
    return switch (codepoint) {
        ' '...'~' => codepoint - ' ',
        '─' => 95,
        '│' => 96,
        '┌' => 97,
        '┐' => 98,
        '└' => 99,
        '┘' => 100,
        '├' => 101,
        '┤' => 102,
        '┬' => 103,
        '┴' => 104,
        '┼' => 105,
        '═' => 106,
        '║' => 107,
        '╔' => 108,
        '╗' => 109,
        '╚' => 110,
        '╝' => 111,
        '░' => 112,
        '▒' => 113,
        '·' => 114,
        '•' => 115,
        '∞' => 116,
        '…' => 117,
        '⇧' => 118,
        '×' => 119,
        '¿' => 120,
        '¡' => 121,
        '±' => 122,
        '≠' => 123,
        else => getCodepointIdx('×'),
    };
}

fn popCheat(_: *anyopaque) ?g.Cheat {
    const result = cheat;
    cheat = null;
    return result;
}

fn serialMessageCallback(data: [*c]const u8) callconv(.c) void {
    cheat = g.Cheat.parse(std.mem.span(data));
}

fn openFile(ptr: *anyopaque, file_path: []const u8, mode: g.Runtime.FileMode, buffer: []u8) anyerror!*anyopaque {
    log.debug("Open file {s} to {t}", .{ file_path, mode });
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file_options: c_int = switch (mode) {
        .read => api.FILE_READ_DATA,
        .write => api.FILE_WRITE,
    };
    var path_buf: [50]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&path_buf, "{s}/{s}", .{ save_dir, file_path });
    path_buf[full_path.len] = 0;
    const file_ptr = self.playdate.file.open(full_path.ptr, file_options) orelse {
        log.err(
            "Error on opening file {s} in mode {s}: {s}",
            .{ full_path, @tagName(mode), self.playdate.file.geterr() },
        );
        return error.IOError;
    };
    const file_wrapper = try self.alloc.create(io.FileWrapper);
    file_wrapper.* = switch (mode) {
        .read => .{ .reader = .init(self.playdate, file_ptr, buffer) },
        .write => .{ .writer = .init(self.playdate, file_ptr, buffer) },
    };
    log.debug("Opened file {*}", .{file_wrapper});
    return file_wrapper;
}

fn closeFile(ptr: *anyopaque, file: *anyopaque) void {
    log.debug("Close file {*}", .{file});
    const self: *Self = @ptrCast(@alignCast(ptr));
    const file_wrapper: *io.FileWrapper = @ptrCast(@alignCast(file));
    if (file_wrapper.* == .writer)
        file_wrapper.writer.interface.flush() catch |err| {
            std.debug.panic("Error on flushing file {any}: {any}", .{ file, err });
        };
    if (self.playdate.file.close(file_wrapper.sdfile()) < 0) {
        std.debug.panic("Error on closing file {any}: {s}", .{ file, self.playdate.file.geterr() });
    }
    self.alloc.destroy(file_wrapper);
}

fn readFile(_: *anyopaque, file: *anyopaque) *std.Io.Reader {
    const file_wrapper: *io.FileWrapper = @ptrCast(@alignCast(file));
    log.debug("Prepare a reader to read from the file {*}", .{file_wrapper});
    return &file_wrapper.reader.interface;
}

fn writeToFile(_: *anyopaque, file: *anyopaque) *std.Io.Writer {
    const file_wrapper: *io.FileWrapper = @ptrCast(@alignCast(file));
    log.debug("Prepare a writer to write to the file {*}", .{file_wrapper});
    return &file_wrapper.writer.interface;
}

fn isFileExists(ptr: *anyopaque, file_path: []const u8) anyerror!bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    var result = ExpectedFile{ .file_name = file_path };
    if (self.playdate.file.listfiles(save_dir, validateFile, &result, 0) < 0) {
        log.err("Error on listing files inside {s}: {s}", .{ save_dir, self.playdate.file.geterr() });
        return error.IOError;
    }

    return result.is_found;
}

fn deleteFileIfExists(ptr: *anyopaque, file_path: []const u8) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (!try isFileExists(ptr, file_path)) return;

    var buf: [50]u8 = undefined;
    const full_path = try std.fmt.bufPrint(&buf, "{s}/{s}", .{ save_dir, file_path });
    buf[full_path.len] = 0;
    if (self.playdate.file.unlink(full_path.ptr, 0) < 0) {
        log.err("Error on deleting file {s}: {s}", .{ file_path, self.playdate.file.geterr() });
        return error.IOError;
    }
}

const ExpectedFile = struct {
    file_name: []const u8,
    is_found: bool = false,
};

fn validateFile(file_name: [*c]const u8, userdata: ?*anyopaque) callconv(.c) void {
    const expected_file: *ExpectedFile = @ptrCast(@alignCast(userdata));
    const actual_file = std.mem.sliceTo(file_name, 0);
    expected_file.is_found = std.mem.eql(u8, expected_file.file_name, actual_file);
}
