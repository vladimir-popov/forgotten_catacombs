const std = @import("std");
const api = @import("api.zig");
const gm = @import("game");
const tools = @import("tools");
const cmp = gm.components;
const Allocator = @import("Allocator.zig");

const Self = @This();

playdate: *api.PlaydateAPI,
font: *api.LCDFont,

pub fn init(playdate: *api.PlaydateAPI) Self {
    const err: ?*[*c]const u8 = null;
    const font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", err) orelse {
        const err_msg = err orelse "Unknown error.";
        std.debug.panic("Error on load font: {s}", .{err_msg});
    };

    playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeFillBlack);
    playdate.graphics.setFont(font);

    return .{ .playdate = playdate, .font = font };
}

pub fn deinit(self: Self) void {
    self.playdate.system.realloc(self.font, 0);
}

pub fn any(self: *Self) gm.AnyRuntime {
    var millis: c_uint = undefined;
    _ = self.playdate.system.getSecondsSinceEpoch(&millis);
    var rnd = std.Random.DefaultPrng.init(@intCast(millis));
    return .{
        .context = self,
        .alloc = Allocator.allocator(self.playdate),
        .rand = rnd.random(),
        .vtable = .{
            .readButton = readButton,
            .drawWalls = drawWalls,
            .drawSprite = drawSprite,
        },
    };
}

pub fn log(self: Self, comptime fmt: []const u8, args: anytype) void {
    const full_fmt = "INFO: " ++ fmt ++ "\n";
    var buffer: [128]u8 = undefined;
    const str = std.fmt.bufPrintZ(&buffer, full_fmt, args) catch
        return self.playdate.system.logToConsole("Message too long to show in log.");
    self.playdate.system.logToConsole("%s", str.ptr);
}

// ======== Private methods: ==============

fn readButton(ptr: *anyopaque) anyerror!?gm.Button.Type {
    var self: *Self = @ptrCast(@alignCast(ptr));
    var button: api.PDButtons = undefined;
    self.playdate.system.getButtonState(&button, null, null);
    if (button == 0)
        return null
    else
        return @intCast(button);
}

fn drawWalls(_: *anyopaque, _: *const gm.Level.Walls) anyerror!void {}

fn drawSprite(ptr: *anyopaque, sprite: *const gm.Sprite, row: u8, col: u8) anyerror!void {
    var self: *Self = @ptrCast(@alignCast(ptr));
    self.log("Draw {s}", .{sprite.letter});
    _ = self.playdate.graphics.drawText(sprite.letter.ptr, sprite.letter.len, .UTF8Encoding, col, row);
}
