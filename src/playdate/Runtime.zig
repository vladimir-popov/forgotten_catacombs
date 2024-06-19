const std = @import("std");
const api = @import("api.zig");
const game = @import("game");
const Allocator = @import("Allocator.zig");

const log = std.log.scoped(.runtime);

const Self = @This();

const ButtonsLog = struct {
    button: api.PDButtons = 0,
    pressed_at: u32 = 0,
    released_at: u32 = 0,
    press_count: u16 = 0,
};

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
prng: std.rand.Xoshiro256,
font: ?*api.LCDFont,
button_log: ButtonsLog = .{},

pub fn create(playdate: *api.PlaydateAPI) !*Self {
    const err: ?*[*c]const u8 = null;
    const font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font: {s}", .{err_msg});
    };
    errdefer _ = playdate.system.realloc(font, 0);

    playdate.graphics.setFont(font);
    playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeFillWhite);

    var millis: c_uint = undefined;
    _ = playdate.system.getSecondsSinceEpoch(&millis);

    const alloc = Allocator.allocator(playdate);
    const runtime = try alloc.create(Self);
    runtime.* = .{
        .playdate = playdate,
        .alloc = alloc,
        .prng = std.Random.DefaultPrng.init(@intCast(millis)),
        .font = font,
    };

    return runtime;
}

pub fn destroy(self: *Self) void {
    self.playdate.realloc(0, self.font);
    self.alloc.destroy(self);
}

pub fn any(self: *Self) game.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .rand = self.prng.random(),
        .vtable = &.{
            .currentMillis = currentMillis,
            .readButtons = readButtons,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .drawLabel = drawLabel,
        },
    };
}

// ======== Private methods: ==============

fn currentMillis(ptr: *anyopaque) i64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.playdate.system.getCurrentTimeMilliseconds();
}

fn readButtons(ptr: *anyopaque) anyerror!?game.AnyRuntime.Buttons {
    const self: *Self = @ptrCast(@alignCast(ptr));

    var current_buttons: api.PDButtons = 0;
    var pressed_buttons: api.PDButtons = 0;
    var released_button: api.PDButtons = 0;
    self.playdate.system.getButtonState(&current_buttons, &pressed_buttons, &released_button);

    if (pressed_buttons > 0) {
        self.button_log.press_count = if (pressed_buttons == self.button_log.button)
            self.button_log.press_count + 1
        else
            1;
        self.button_log.pressed_at = self.playdate.system.getCurrentTimeMilliseconds();
        self.button_log.button = pressed_buttons;
        const press_delay = self.button_log.pressed_at - self.button_log.released_at;
        if (self.button_log.press_count > 1 and press_delay < game.AnyRuntime.DOUBLE_PRESS_DELAY_MS)
            return .{ .code = current_buttons, .state = .double_pressed }
        else
            return .{ .code = pressed_buttons, .state = .pressed };
    } else if (current_buttons > 0) {
        const hold_delay = self.playdate.system.getCurrentTimeMilliseconds() - self.button_log.pressed_at;
        if (hold_delay > game.AnyRuntime.HOLD_DELAY_MS)
            return .{ .code = current_buttons, .state = .hold };
    } else if (released_button > 0) {
        self.button_log.released_at = self.playdate.system.getCurrentTimeMilliseconds();
    }
    return null;
}

fn drawDungeon(ptr: *anyopaque, screen: *const game.Screen, dungeon: *const game.Dungeon) anyerror!void {
    // separate dung and stats:
    var self: *Self = @ptrCast(@alignCast(ptr));
    const x = (game.DISPLAY_DUNG_COLS + 1) * game.FONT_WIDTH;
    self.playdate.graphics.drawLine(x, 0, x, game.DISPLPAY_HEGHT, 1, @intFromEnum(api.LCDSolidColor.ColorWhite));
    self.playdate.graphics.drawLine(x + 2, 0, x + 2, game.DISPLPAY_HEGHT, 1, @intFromEnum(api.LCDSolidColor.ColorWhite));

    // draw dung:
    var itr = dungeon.cellsInRegion(screen.region) orelse return;
    var position = game.Position{ .point = screen.region.top_left };
    var sprite = game.Sprite{ .letter = undefined };
    while (itr.next()) |cell| {
        sprite.letter = switch (cell) {
            .nothing => " ",
            .floor => ".",
            .wall => "#",
            .door => |door| if (door == .opened) "\'" else "+",
        };
        try drawSprite(ptr, screen, &sprite, &position);
        position.point.move(.right);
        if (!screen.region.containsPoint(position.point)) {
            position.point.col = screen.region.top_left.col;
            position.point.move(.down);
        }
    }
}

fn drawSprite(
    ptr: *anyopaque,
    screen: *const game.Screen,
    sprite: *const game.Sprite,
    position: *const game.Position,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        const self: *Self = @ptrCast(@alignCast(ptr));
        const y: c_int = game.FONT_HEIGHT * @as(c_int, position.point.row - screen.region.top_left.row + 1);
        const x: c_int = game.FONT_WIDTH * @as(c_int, position.point.col - screen.region.top_left.col + 1);
        _ = self.playdate.graphics.drawText(sprite.letter.ptr, sprite.letter.len, .UTF8Encoding, x, y);
    }
}

fn drawLabel(ptr: *anyopaque, label: []const u8, row: u8, col: u8) !void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    _ = self.playdate.graphics.drawText(
        label.ptr,
        label.len,
        .UTF8Encoding,
        @as(c_int, col) * game.FONT_WIDTH,
        @as(c_int, row) * game.FONT_HEIGHT,
    );
}
