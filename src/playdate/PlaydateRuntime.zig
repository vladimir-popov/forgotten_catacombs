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
font: ?*api.LCDFont,
last_button: *LastButton,

pub fn init(playdate: *api.PlaydateAPI) !Self {
    const err: ?*[*c]const u8 = null;

    const font = playdate.graphics.loadFont("sprites-font.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font for text: {s}", .{err_msg});
    };
    errdefer _ = playdate.system.realloc(font, 0);

    const alloc = Allocator.allocator(playdate);
    const last_button = try alloc.create(LastButton);
    errdefer alloc.destroy(last_button);

    playdate.graphics.setFont(font);
    playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    playdate.system.setSerialMessageCallback(serialMessageCallback);
    playdate.system.setButtonCallback(LastButton.handleEvent, last_button, 4);

    return .{
        .playdate = playdate,
        .alloc = alloc,
        .font = font,
        .last_button = last_button,
    };
}

pub fn deinit(self: *Self) void {
    self.playdate.realloc(0, self.font);
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
    // draw text:
    const x = @as(c_int, position_on_display.col - 1) * g.SPRITE_WIDTH;
    const y = @as(c_int, position_on_display.row - 1) * g.SPRITE_HEIGHT;

    // the count of codepoints or 0 terminated string should be passed to the playdate api
    // to draw the text. To avoid extra argument, we will pass 0 terminated string here.
    var buf: [5]u8 = .{0} ** 5;
    const len = try std.unicode.utf8Encode(codepoint, &buf);
    try self.drawTextOnDisplay(buf[0 .. len + 1], mode, x, y);
}

fn drawText(ptr: *anyopaque, text: []const u8, position_on_display: p.Point, mode: g.Render.DrawingMode) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    // draw text:
    const x = @as(c_int, position_on_display.col - 1) * g.SPRITE_WIDTH;
    const y = @as(c_int, position_on_display.row - 1) * g.SPRITE_HEIGHT;
    // if (text[text.len - 1] == ' ') {
    //     var buf: [g.DISPLAY_COLS]u8 = undefined;
    //     std.mem.copyForwards(u8, &buf, text);
    //     // to avoid trimming of the string with spaces at the end,
    //     // here we replace the last one by the special symbol '¶'(0xC2 0xB6 in utf8).
    //     buf[text.len - 1] = '\xC2';
    //     // this is safe, because the text is sentinel-terminated slice and has one extra symbol.
    //     buf[text.len] = '\xB6';
    //     buf[text.len + 1] = 0;
    //     try self.drawTextOnDisplay(buf[0 .. text.len + 1], mode, x, y);
    // } else {
    //     try self.drawTextOnDisplay(text, mode, x, y);
    // }
        try self.drawTextOnDisplay(text, mode, x, y);
}

fn drawTextOnDisplay(
    self: *Self,
    text: []const u8,
    mode: g.Render.DrawingMode,
    x: c_int,
    y: c_int,
) !void {
    if (mode == .inverted) {
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeInverted);
        _ = self.playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, x, y);
        self.playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    } else {
        _ = self.playdate.graphics.drawText(text.ptr, text.len, .UTF8Encoding, x, y);
    }
}

fn getCheat(_: *anyopaque) ?g.Cheat {
    const result = cheat;
    cheat = null;
    return result;
}

fn serialMessageCallback(data: [*c]const u8) callconv(.C) void {
    cheat = g.Cheat.parse(std.mem.span(data));
}
