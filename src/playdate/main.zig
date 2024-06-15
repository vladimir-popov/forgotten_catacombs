const std = @import("std");
const game = @import("game");
const api = @import("api.zig");
const tools = @import("tools");

const Runtime = @import("Runtime.zig");

pub const log_level: std.log.Level = .warn;

pub const std_options = .{
    .logFn = writeLog,
};

fn writeLog(
    comptime lvl: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    if (lvl == log_level) {
        var buffer = [_]u8{0} ** 128;
        _ = std.fmt.bufPrint(&buffer, format, args) catch |err|
            std.debug.panic("Error {any} on log {s}", .{ err, format });
        playdate_log_to_console("%s (%s) %s", @tagName(lvl), @tagName(scope), (&buffer).ptr);
    }
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    return_address: ?usize,
) noreturn {
    _ = error_return_trace;
    _ = return_address;
    playdate_error_to_console("%s", msg.ptr);
    while (true) {}
}

var playdate_error_to_console: *const fn (fmt: [*c]const u8, ...) callconv(.C) void = undefined;
var playdate_log_to_console: *const fn (fmt: [*c]const u8, ...) callconv(.C) void = undefined;

pub export fn eventHandler(playdate: *api.PlaydateAPI, event: api.PDSystemEvent, arg: u32) callconv(.C) c_int {
    _ = arg;
    switch (event) {
        .EventInit => {
            playdate_error_to_console = playdate.system.@"error";
            playdate_log_to_console = playdate.system.logToConsole;

            const err: ?*[*c]const u8 = null;
            const font = playdate.graphics.loadFont("Roobert-11-Mono-Condensed.pft", err) orelse {
                const err_msg = err orelse "Unknown error.";
                std.debug.panic("Error on load font: {s}", .{err_msg});
            };

            playdate.graphics.setFont(font);
            playdate.graphics.setDrawMode(api.LCDBitmapDrawMode.DrawModeFillWhite);

            const session: *game.GameSession = game.GameSession.create(Runtime.any(playdate)) catch
                @panic("Error on creating universe");

            playdate.system.setUpdateCallback(update_and_render, session);
        },
        else => {},
    }
    return 0;
}

fn update_and_render(userdata: ?*anyopaque) callconv(.C) c_int {
    const session: *game.GameSession = @ptrCast(@alignCast(userdata.?));
    const playdate: *api.PlaydateAPI = @ptrCast(@alignCast(session.runtime.context));

    playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorBlack));

    session.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
