const std = @import("std");
const api = @import("api.zig");
const g = @import("game");
const c = g.components;
const p = g.primitives;

const Allocator = @import("Allocator.zig");
const LastButton = @import("LastButton.zig");

const log = std.log.scoped(.playdate_runtime);

const PlaydateRuntime = @This();

// This is a global var because the
// serialMessageCallback doesn't receive custom data
var cheat: ?g.Cheat = null;

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
bitmap_table: *api.LCDBitmapTable,
last_button: *LastButton,
is_dev_mode: bool = false,

pub fn init(playdate: *api.PlaydateAPI) !PlaydateRuntime {
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

    return .{
        .playdate = playdate,
        .alloc = alloc,
        .bitmap_table = bitmap_table,
        .last_button = last_button,
    };
}

pub fn deinit(self: *PlaydateRuntime) void {
    self.playdate.realloc(0, self.bitmap_table);
    self.playdate.realloc(0, self.last_button);
}

pub fn runtime(self: *PlaydateRuntime) g.Runtime {
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
            .drawText = drawText,
            .openFile = openFile,
            .closeFile = closeFile,
            .readFile = readFile,
            .writeFile = writeFile,
        },
    };
}

// ======== Private methods: ==============

fn isDevMode(ptr: *anyopaque) bool {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    return self.is_dev_mode;
}

fn currentMillis(ptr: *anyopaque) c_uint {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    return self.playdate.system.getCurrentTimeMilliseconds();
}

fn addMenuItem(
    ptr: *anyopaque,
    title: []const u8,
    game_object: *anyopaque,
    callback: g.Runtime.MenuItemCallback,
) ?*anyopaque {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    return self.playdate.system.addMenuItem(title.ptr, callback, game_object).?;
}

fn removeAllMenuItems(ptr: *anyopaque) void {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    self.playdate.system.removeAllMenuItems();
}

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Button {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));

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
    var self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    self.playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorBlack));
}

fn drawSprite(ptr: *anyopaque, codepoint: g.Codepoint, position_on_display: p.Point, mode: g.DrawingMode) !void {
    var self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    const x = @as(c_int, position_on_display.col - 1) * g.SPRITE_WIDTH;
    const y = @as(c_int, position_on_display.row - 1) * g.SPRITE_HEIGHT;
    if (mode == .inverted)
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeInverted)
    else
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    self.playdate.graphics.drawBitmap(self.getBitmap(codepoint), x, y, .BitmapUnflipped);
}

fn drawText(ptr: *anyopaque, text: []const u8, position_on_display: p.Point, mode: g.DrawingMode) !void {
    var itr = std.unicode.Utf8View.initUnchecked(text).iterator();
    var position = position_on_display;
    while (itr.nextCodepoint()) |codepoint| {
        try drawSprite(ptr, codepoint, position, mode);
        position.move(.right);
    }
}

fn getBitmap(self: PlaydateRuntime, codepoint: g.Codepoint) *api.LCDBitmap {
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
        else => getCodepointIdx('×'),
    };
}

fn popCheat(_: *anyopaque) ?g.Cheat {
    const result = cheat;
    cheat = null;
    return result;
}

fn serialMessageCallback(data: [*c]const u8) callconv(.C) void {
    cheat = g.Cheat.parse(std.mem.span(data));
}

fn openFile(ptr: *anyopaque, file_path: []const u8, mode: g.Runtime.FileMode) anyerror!*anyopaque {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    const file_options = switch (mode) {
        .read => api.FILE_READ_DATA,
        .write => api.FILE_WRITE,
    };
    return self.playdate.file.open(file_path, file_options) orelse {
        std.debug.panic("{s}", .{self.playdate.file.geterr()});
    };
}

fn closeFile(ptr: *anyopaque, file: *anyopaque) void {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    if (self.playdate.file.close(file) < 0)
        std.debug.panic("{s}", .{self.playdate.file.geterr()});
}

fn readFile(ptr: *anyopaque, file: *anyopaque, buffer: []u8) anyerror!usize {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    const result = self.playdate.file.read(file, buffer.ptr, buffer.len);
    if (result < 0)
        std.debug.panic("{s}", .{self.playdate.file.geterr()});
    return @intCast(result);
}

fn writeFile(ptr: *anyopaque, file: *anyopaque, bytes: []const u8) anyerror!usize {
    const self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    const result = self.playdate.file.write(file, bytes.ptr, bytes.len);
    if (result < 0)
        std.debug.panic("{s}", .{self.playdate.file.geterr()});
    return @intCast(result);
}
