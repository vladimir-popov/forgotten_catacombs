const std = @import("std");
const api = @import("api.zig");
const game = @import("game");
const Allocator = @import("Allocator.zig");

const FONT_HEIGHT: u16 = 16;
const FONT_WIDHT: u16 = 8;

const PRESS_BUTTON_DELAY_MS = 100;

const log = std.log.scoped(.runtime);

const Self = @This();

playdate: *api.PlaydateAPI,
alloc: std.mem.Allocator,
prng: std.rand.Xoshiro256,
font: ?*api.LCDFont,
button: api.PDButtons = 0,

pub fn create(playdate: *api.PlaydateAPI) Self {
    const err: ?*[*c]const u8 = null;
    const font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font: {s}", .{err_msg});
    };

    playdate.graphics.setFont(font);
    playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeFillWhite);

    var millis: c_uint = undefined;
    _ = playdate.system.getSecondsSinceEpoch(&millis);

    return .{
        .playdate = playdate,
        .alloc = Allocator.allocator(playdate),
        .prng = std.Random.DefaultPrng.init(@intCast(millis)),
        .font = font,
    };
}

pub fn deinit(self: Self) void {
    self.playdate.realloc(0, self.font);
}

pub fn any(self: *Self) game.AnyRuntime {
    return .{
        .context = self,
        .alloc = self.alloc,
        .rand = self.prng.random(),
        .vtable = &.{
            .readButton = readButton,
            .drawDungeon = drawDungeon,
            .drawSprite = drawSprite,
            .currentMillis = currentMillis,
        },
    };
}

// ======== Private methods: ==============

fn currentMillis(ptr: *anyopaque) i64 {
    const self: *Self = @ptrCast(@alignCast(ptr));
    return self.playdate.system.getCurrentTimeMilliseconds();
}

fn readButton(ptr: *anyopaque) anyerror!game.AnyRuntime.Button.Type {
    const self: *Self = @ptrCast(@alignCast(ptr));
    if (self.button == 0)
        self.playdate.system.getButtonState(null, &self.button, null)
    else
        self.playdate.system.getButtonState(null, null, &self.button);
    return self.button;
}

fn drawDungeon(ptr: *anyopaque, screen: *const game.Screen, dungeon: *const game.Dungeon) anyerror!void {
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
        const y: c_int = FONT_HEIGHT * (position.point.row - screen.region.top_left.row + 1);
        const x: c_int = FONT_WIDHT * (position.point.col - screen.region.top_left.col + 1);
        _ = self.playdate.graphics.drawText(sprite.letter.ptr, sprite.letter.len, .UTF8Encoding, x, y);
    }
}
