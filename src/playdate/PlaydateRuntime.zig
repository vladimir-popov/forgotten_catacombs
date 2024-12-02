const std = @import("std");
const api = @import("api.zig");
const g = @import("game");
const c = g.components;
const p = g.primitives;

const Allocator = @import("Allocator.zig");

const log = std.log.scoped(.playdate_runtime);

const Self = @This();

const LastButton = struct {
    const Btn = struct {
        game_button: g.Button.GameButton,
        is_pressed: bool,
        pressed_at: u32,
        pressed_count: u8,
    };

    button: ?Btn = null,

    fn handleEvent(
        button: api.PDButtons,
        down: c_int,
        when: u32,
        ptr: ?*anyopaque,
    ) callconv(.C) c_int {
        const self: *LastButton = @ptrCast(@alignCast(ptr));
        const is_pressed = down > 0;
        if (g.Button.GameButton.fromCode(button)) |game_button| {
            if (self.button) |*current_button| {
                return self.handleEventWithCurrentButton(current_button, game_button, is_pressed, when);
            } else if (is_pressed) {
                // the first press:
                self.button = .{
                    .game_button = game_button,
                    .is_pressed = true,
                    .pressed_at = when,
                    .pressed_count = 1,
                };
            } else {
                self.button = null;
            }
        }
        return 0;
    }

    fn handleEventWithCurrentButton(
        self: *LastButton,
        current_button: *Btn,
        game_button: g.Button.GameButton,
        is_pressed: bool,
        when: u32,
    ) callconv(.C) c_int {
        // event for the same button
        if (current_button.game_button == game_button) {
            if (is_pressed) {
                // the current button pressed again
                current_button.is_pressed = true;
                current_button.pressed_at = when;
                if ((when - current_button.pressed_at) < g.DOUBLE_PUSH_DELAY_MS) {
                    current_button.pressed_count += 1;
                } else {
                    current_button.pressed_count = 1;
                }
            } else {
                current_button.is_pressed = false;
            }
        } else {
            // event for another button
            if (!current_button.is_pressed and is_pressed) {
                self.button = .{
                    .game_button = game_button,
                    .is_pressed = true,
                    .pressed_at = when,
                    .pressed_count = 1,
                };
            } else {
                self.button = null;
            }
        }
        return 0;
    }
};

var cheat: ?g.Cheat = null;

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
bitmap_table: *api.LCDBitmapTable,
last_button: *LastButton,

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

pub fn deinit(self: *Self) void {
    self.playdate.realloc(0, self.bitmap_table);
}

pub fn runtime(self: *Self) g.Runtime {
    return .{
        .context = self,
        .vtable = &.{
            .getCheat = getCheat,
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

    if (cheat) |_| return .{ .game_button = .cheat, .state = .pressed };

    if (self.last_button.button) |btn| {
        // handle only released button
        if (!btn.is_pressed) {
            self.last_button.button = null;
            // stop handle held button right after release
            if ((currentMillis(self) - btn.pressed_at) > g.HOLD_DELAY_MS) {
                return null;
            }
            return .{
                .game_button = btn.game_button,
                .state = if (btn.pressed_count > 1)
                    .double_pressed
                else
                    .pressed,
            };
        } else if ((currentMillis(self) - btn.pressed_at) > g.HOLD_DELAY_MS) {
            return .{
                .game_button = btn.game_button,
                .state = .hold,
            };
        }
    }
    return null;
}

fn clearDisplay(ptr: *anyopaque) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorBlack));
}

fn drawSprite(ptr: *anyopaque, codepoint: g.Codepoint, position_on_display: p.Point, mode: g.Render.DrawingMode) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
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

fn getBitmap(self: Self, codepoint: g.Codepoint) *api.LCDBitmap {
    const idx = getCodepointIdx(codepoint);
    if (codepoint == 'F') log.warn("Getting bitmap for F on index {d}", .{idx});
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
        '▓' => 114,
        '•' => 115,
        '∞' => 116,
        '…' => 117,
        '¿' => 118,
        '×' => 119,
        else => getCodepointIdx('¿'),
    };
}

fn getCheat(_: *anyopaque) ?g.Cheat {
    const result = cheat;
    cheat = null;
    return result;
}

fn serialMessageCallback(data: [*c]const u8) callconv(.C) void {
    cheat = g.Cheat.parse(std.mem.span(data));
}
