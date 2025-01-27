const std = @import("std");
const api = @import("api.zig");
const g = @import("game");
const c = g.components;
const p = g.primitives;

const Allocator = @import("Allocator.zig");

const log = std.log.scoped(.playdate_runtime);

const HOLD_DELAY_MS = 700;
const REPEATE_DELAY_MS = 100;

const PlaydateRuntime = @This();

const LastButton = struct {
    const State = enum { pressed, released };
    buttons: c_int = 0,
    /// 0 means that all buttons are released now
    pressed_at: u32 = 0,
    was_repeated: bool = false,

    pub fn pop(self: *LastButton, now_ms: u32) ?g.Button {
        if (g.Button.GameButton.fromCode(self.buttons)) |game_button| {
            if (self.pressed_at == 0) {
                // ignore release for repeated button
                if (self.was_repeated) {
                    self.* = .{};
                    return null;
                }
                self.* = .{};
                return .{ .game_button = game_button, .state = .released };
            }
            // repeat for pressed arrows only
            else if (game_button.isMove() and now_ms - self.pressed_at > REPEATE_DELAY_MS) {
                self.pressed_at = now_ms;
                self.was_repeated = true;
                return .{ .game_button = game_button, .state = .hold };
            }
            // the button is held
            else if (now_ms - self.pressed_at > HOLD_DELAY_MS) {
                self.* = .{};
                return .{ .game_button = game_button, .state = .hold };
            }
        }
        return null;
    }

    /// The ButtonCallback handler.
    ///
    /// The function is called for each button up/down event
    /// (possibly multiple events on the same button) that occurred during
    /// the previous update cycle. At the default 30 FPS, a queue size of 5
    /// should be adequate. At lower frame rates/longer frame times, the
    /// queue size should be extended until all button presses are caught.
    ///
    /// See: https://sdk.play.date/2.6.2/Inside%20Playdate%20with%20C.html#f-system.setButtonCallback
    ///
    fn handleEvent(
        buttons: api.PDButtons,
        down: c_int,
        when: u32,
        ptr: ?*anyopaque,
    ) callconv(.C) c_int {
        const self: *LastButton = @ptrCast(@alignCast(ptr));
        if (down > 0) {
            if (self.pressed_at > 0)
                // additional buttons have been pressed
                self.buttons |= buttons
            else
                // nothing pressed before, new buttons have been pressed
                self.buttons = buttons;

            self.pressed_at = when;
        } else {
            self.pressed_at = 0;
        }
        return 0;
    }
};

// This is a global var because the
// serialMessageCallback doesn't receive custom data
var cheat: ?g.Cheat = null;

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
bitmap_table: *api.LCDBitmapTable,
last_button: *LastButton,

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
    errdefer alloc.destroy(last_button);

    playdate.system.setSerialMessageCallback(serialMessageCallback);
    playdate.system.setButtonCallback(LastButton.handleEvent, last_button, 4);

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
            .popCheat = popCheat,
            .addMenuItem = addMenuItem,
            .removeAllMenuItems = removeAllMenuItems,
            .currentMillis = currentMillis,
            .readPushedButtons = readPushedButtons,
            .clearDisplay = clearDisplay,
            .drawSprite = drawSprite,
            .drawText = drawText,
        },
    };
}

// ======== Private methods: ==============

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

fn drawSprite(ptr: *anyopaque, codepoint: g.Codepoint, position_on_display: p.Point, mode: g.Render.DrawingMode) !void {
    var self: *PlaydateRuntime = @ptrCast(@alignCast(ptr));
    const x = @as(c_int, position_on_display.col - 1) * g.SPRITE_WIDTH;
    const y = @as(c_int, position_on_display.row - 1) * g.SPRITE_HEIGHT;
    if (mode == .inverted)
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeInverted)
    else
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    self.playdate.graphics.drawBitmap(self.getBitmap(codepoint), x, y, .BitmapUnflipped);
}

fn drawText(ptr: *anyopaque, text: []const u8, position_on_display: p.Point, mode: g.Render.DrawingMode) !void {
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
        '↕' => 118,
        '×' => 119,
        else => getCodepointIdx('¿'),
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
