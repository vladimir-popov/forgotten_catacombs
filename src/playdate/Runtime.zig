const std = @import("std");
const api = @import("api.zig");
const game = @import("game");
const tools = @import("tools");
const cmp = game.components;
const Allocator = @import("Allocator.zig");

const Self = @This();

const FONT_HEIGHT: u16 = 16;
const FONT_WIDHT: u16 = 8;

const log = std.log.scoped(.runtime);

var rnd: std.rand.Xoshiro256 = std.rand.DefaultPrng.init(0);

pub fn any(playdate: *api.PlaydateAPI) game.AnyRuntime {
    // var millis: c_uint = undefined;
    // _ = self.playdate.system.getSecondsSinceEpoch(&millis);
    // var rnd = std.Random.DefaultPrng.init(@intCast(millis));
    return .{
        .context = playdate,
        .alloc = Allocator.allocator(playdate),
        .rand = rnd.random(),
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
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(ptr));
    return playdate.system.getCurrentTimeMilliseconds();
}

fn readButton(ptr: *anyopaque) anyerror!game.Button.Type {
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(ptr));
    var button: api.PDButtons = undefined;
    playdate.system.getButtonState(null, &button, null);
    return @truncate(button);
}

fn drawDungeon(ptr: *anyopaque, screen: *const game.Screen, dungeon: *const game.Dungeon) anyerror!void {
    var itr = dungeon.cellsInRegion(screen.region) orelse return;
    var position = game.components.Position{ .point = screen.region.top_left };
    var sprite = game.components.Sprite{ .letter = undefined };
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
    sprite: *const cmp.Sprite,
    position: *const cmp.Position,
) anyerror!void {
    if (screen.region.containsPoint(position.point)) {
        const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(ptr));
        const y: c_int = FONT_HEIGHT * (position.point.row - screen.region.top_left.row + 1);
        const x: c_int = FONT_WIDHT * (position.point.col - screen.region.top_left.col + 1);
        _ = playdate.graphics.drawText(sprite.letter.ptr, sprite.letter.len, .UTF8Encoding, x, y);
    }
}
