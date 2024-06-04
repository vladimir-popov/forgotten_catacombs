const std = @import("std");
const game = @import("game");
const api = @import("api.zig");
const tools = @import("tools");

const Runtime = @import("Runtime.zig");

const CurrentPlatform = tools.Platform.Playdate;

pub const std_options = .{
    .logFn = writeLog,
};

fn writeLog(
    comptime message_level: std.log.Level,
    comptime _: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    _ = format;
    _ = args;
    _ = message_level;
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

const GlobalState = struct {
    runtime: Runtime,
    universe: game.Universe,

    pub fn create(playdate: *api.PlaydateAPI) !*GlobalState {
        var state: *GlobalState = @ptrCast(@alignCast(playdate.system.realloc(null, @sizeOf(GlobalState))));
        state.runtime = Runtime.init(playdate);
        state.universe = try game.init(state.runtime.any());
        return state;
    }
};

pub export fn eventHandler(playdate: *api.PlaydateAPI, event: api.PDSystemEvent, arg: u32) callconv(.C) c_int {
    _ = arg;
    switch (event) {
        .EventInit => {
            playdate_error_to_console = playdate.system.@"error";

            const global_state: *anyopaque = GlobalState.create(playdate) catch |err|
                std.debug.panic("Error {any} on init global state", .{err});
            playdate.system.setUpdateCallback(update_and_render, global_state);
        },
        else => {},
    }
    return 0;
}

fn update_and_render(userdata: ?*anyopaque) callconv(.C) c_int {
    const gst: *GlobalState = @ptrCast(@alignCast(userdata.?));
    gst.runtime.playdate.graphics.clear(@intFromEnum(api.LCDSolidColor.ColorWhite));
    gst.universe.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
