const std = @import("std");
const api = @import("api.zig");
const g = @import("game");
const c = g.components;
const p = g.primitives;

const Allocator = @import("Allocator.zig");

const log = std.log.scoped(.runtime);

const Self = @This();

const ButtonsLog = struct {
    button: api.PDButtons = 0,
    pressed_at: u32 = 0,
    released_at: u32 = 0,
    release_count: u16 = 0,
};

var cheat: ?g.Cheat = null;

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
text_font: ?*api.LCDFont,
sprites_font: ?*api.LCDFont,
button_log: ButtonsLog = .{},

pub fn init(playdate: *api.PlaydateAPI) !Self {
    const err: ?*[*c]const u8 = null;

    const text_font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font for text: {s}", .{err_msg});
    };
    errdefer _ = playdate.system.realloc(text_font, 0);

    const sprites_font = playdate.graphics.loadFont("sprites-font.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font for sprites: {s}", .{err_msg});
    };
    errdefer _ = playdate.system.realloc(sprites_font, 0);

    playdate.graphics.setFont(sprites_font);
    playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeCopy);
    playdate.system.setSerialMessageCallback(serialMessageCallback);

    var millis: c_uint = undefined;
    _ = playdate.system.getSecondsSinceEpoch(&millis);

    const alloc = Allocator.allocator(playdate);
    return .{
        .playdate = playdate,
        .alloc = alloc,
        .text_font = text_font,
        .sprites_font = sprites_font,
    };
}

pub fn deinit(self: *Self) void {
    self.playdate.realloc(0, self.text_font);
    self.playdate.realloc(0, self.sprites_font);
}

pub fn any(self: *Self) g.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .vtable = &.{
            .getCheat = getCheat,
            .currentMillis = currentMillis,
            .readPushedButtons = readPushedButtons,
            .clearDisplay = clearDisplay,
            .drawScreenBorder = drawScreenBorder,
            .drawHorizontalBorder = drawHorizontalBorder,
            .drawDungeon = drawDungeon,
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

fn readPushedButtons(ptr: *anyopaque) anyerror!?g.Buttons {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (cheat) |_| return .{ .code = g.Buttons.Cheat, .state = .pushed };

    var current_buttons: api.PDButtons = 0;
    var pressed_buttons: api.PDButtons = 0;
    var released_buttons: api.PDButtons = 0;
    self.playdate.system.getButtonState(&current_buttons, &pressed_buttons, &released_buttons);

    if (pressed_buttons > 0) {
        self.button_log.pressed_at = self.playdate.system.getCurrentTimeMilliseconds();
    } else if (current_buttons > 0 and self.button_log.pressed_at > 0) {
        const hold_delay = self.playdate.system.getCurrentTimeMilliseconds() - self.button_log.pressed_at;
        if (hold_delay > g.HOLD_DELAY_MS)
            return .{ .code = current_buttons, .state = .hold };
    } else if (released_buttons > 0) {
        self.button_log.pressed_at = 0;
        self.button_log.release_count = if (released_buttons == self.button_log.button)
            self.button_log.release_count + 1
        else
            1;
        const now = self.playdate.system.getCurrentTimeMilliseconds();
        self.button_log.button = released_buttons;
        const delay = now - self.button_log.released_at;
        self.button_log.released_at = now;
        if (self.button_log.release_count > 1 and delay < g.DOUBLE_PUSH_DELAY_MS)
            return .{ .code = current_buttons, .state = .double_pushed }
        else
            return .{ .code = released_buttons, .state = .pushed };
    }
    return null;
}

fn clearDisplay(ptr: *anyopaque) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorBlack));
}

fn drawScreenBorder(_: *anyopaque) anyerror!void {}

fn drawHorizontalBorder(ptr: *anyopaque) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    // separate dung and stats:
    const y = g.DISPLAY_HEIGHT - g.FONT_HEIGHT * 2;
    self.playdate.graphics.drawLine(0, y, g.DISPLAY_WIDHT, y, 1, @intFromEnum(api.LCDSolidColor.ColorWhite));
    self.playdate.graphics.drawLine(0, y + 2, g.DISPLAY_WIDHT, y + 2, 1, @intFromEnum(api.LCDSolidColor.ColorWhite));
}

fn drawDungeon(ptr: *anyopaque, screen: g.Screen, dungeon:  g.Dungeon) anyerror!void {
    var itr = dungeon.cellsInRegion(screen.region) orelse return;
    var position = .{ .point = screen.region.top_left };
    var sprite = c.Sprite{ .codepoint = undefined };
    while (itr.next()) |cell| {
        sprite.codepoint = switch (cell) {
            .floor => '.',
            .wall => '#',
            else => ' ',
        };
        try drawSprite(ptr, screen, &sprite, &position, .normal);
        position.point.move(.right);
        if (!screen.region.containsPoint(position.point)) {
            position.point.col = screen.region.top_left.col;
            position.point.move(.down);
        }
    }
}

fn drawSprite(
    ptr: *anyopaque,
    screen: g.Screen,
    sprite: *const c.Sprite,
    position: *const c.Position,
    mode: g.AnyRuntime.DrawingMode,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const y: c_int = g.SPRITE_HEIGHT * @as(c_int, position.point.row - screen.region.top_left.row);
        const x: c_int = g.SPRITE_WIDTH * @as(c_int, position.point.col - screen.region.top_left.col);
        var buf: [4]u8 = undefined;
        const len = try std.unicode.utf8Encode(sprite.codepoint, &buf);
        try self.drawTextWithMode(buf[0..len], mode, x, y);
    }
}

fn drawText(ptr: *anyopaque, text: []const u8, absolute_position: p.Point, mode: g.AnyRuntime.DrawingMode) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    // choose the font for text:
    self.playdate.graphics.setFont(self.text_font);
    // draw text:
    const x = @as(c_int, absolute_position.col) * g.SPRITE_WIDTH;
    const y = @as(c_int, absolute_position.row) * g.SPRITE_HEIGHT;
    try self.drawTextWithMode(text, mode, x, y);
    // revert font for sprites:
    self.playdate.graphics.setFont(self.sprites_font);
}

inline fn drawTextWithMode(
    self: *Self,
    text: []const u8,
    mode: g.AnyRuntime.DrawingMode,
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
