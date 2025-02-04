const std = @import("std");
const api = @import("api.zig");
const g = @import("game");

const PlaydateRuntime = @import("PlaydateRuntime.zig");

pub const std_options = .{
    .log_level = .info,
    .logFn = writeLog,
};

fn writeLog(
    comptime lvl: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer = [_]u8{0} ** 128;
    _ = std.fmt.bufPrint(&buffer, format, args) catch |err|
        std.debug.panic("Error {any} on log {s}", .{ err, format });
    playdate_log_to_console("%s (%s) %s", @tagName(lvl), @tagName(scope), (&buffer).ptr);
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

pub const GlobalState = struct {
    playdate_runtime: PlaydateRuntime,
    game: *g.Game,
};

pub export fn eventHandler(playdate: *api.PlaydateAPI, event: api.PDSystemEvent, arg: u32) callconv(.C) c_int {
    _ = arg;
    switch (event) {
        .EventInit => {
            playdate_error_to_console = playdate.system.@"error";
            playdate_log_to_console = playdate.system.logToConsole;

            var state: *GlobalState = @ptrCast(@alignCast(playdate.system.realloc(null, @sizeOf(GlobalState))));
            state.playdate_runtime = PlaydateRuntime.init(playdate) catch
                @panic("Error on creating Runtime");
            state.game = g.Game.create(
                state.playdate_runtime.alloc,
                state.playdate_runtime.runtime(),
                playdate.system.getCurrentTimeMilliseconds(),
            ) catch
                @panic("Error on creating game session");

            playdate.display.setRefreshRate(0);
            playdate.system.setUpdateCallback(updateAndRender, state);
        },
        else => {},
    }
    return 0;
}

fn updateAndRender(userdata: ?*anyopaque) callconv(.C) c_int {
    const state: *GlobalState = @ptrCast(@alignCast(userdata.?));
    state.game.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    state.playdate_runtime.playdate.system.drawFPS(1, 1);

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
