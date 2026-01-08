const std = @import("std");
const api = @import("api.zig");
const g = @import("game");

const PlaydateRuntime = @import("PlaydateRuntime.zig");

pub const std_options = std.Options{
    .log_level = .info,
    .logFn = writeLog,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        // .{ .scope = .default, .level = .debug },
        // .{ .scope = .playdate_runtime, .level = .debug },
        // .{ .scope = .playdate_io, .level = .debug },
        // .{ .scope = .last_button, .level = .debug },
        // .{ .scope = .runtime, .level = .debug },
        // .{ .scope = .render, .level = .warn },
        // .{ .scope = .visibility, .level = .debug },
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .game, .level = .debug },
        // .{ .scope = .game_session, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .explore_mode, .level = .debug },
        // .{ .scope = .looking_around_mode, .level = .debug },
        // .{ .scope = .save_load_mode, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .cmd, .level = .debug },
        // .{ .scope = .events, .level = .debug },
        // .{ .scope = .action_system, .level = .debug },
    },
};

fn writeLog(
    comptime lvl: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    var buffer: [256]u8 = @splat(0);
    _ = std.fmt.bufPrint(&buffer, format, args) catch |err|
        std.debug.panic("Unhandled error {any} on log {s}", .{ err, format });
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

var playdate_error_to_console: *const fn (fmt: [*c]const u8, ...) callconv(.c) void = undefined;
var playdate_log_to_console: *const fn (fmt: [*c]const u8, ...) callconv(.c) void = undefined;

pub const GlobalState = struct {
    playdate_runtime: PlaydateRuntime,
    game: g.Game,
};

// dirty hack: we need to handle events in playdate_runtime, but it's unavailable inside
// the eventHandler
var global_state: *GlobalState = undefined;

pub export fn eventHandler(playdate: *api.PlaydateAPI, event: api.PDSystemEvent, arg: u32) callconv(.c) c_int {
    _ = arg;
    switch (event) {
        .EventInit => {
            playdate_error_to_console = playdate.system.@"error";
            playdate_log_to_console = playdate.system.logToConsole;

            global_state = @ptrCast(@alignCast(playdate.system.realloc(null, @sizeOf(GlobalState))));
            global_state.playdate_runtime = PlaydateRuntime.init(playdate) catch
                @panic("Error on creating Runtime");
            global_state.game.init(
                global_state.playdate_runtime.alloc,
                global_state.playdate_runtime.runtime(),
                playdate.system.getCurrentTimeMilliseconds(),
            ) catch
                @panic("Error on creating game session");

            playdate.display.setRefreshRate(0);
            playdate.system.setUpdateCallback(updateAndRender, global_state);
        },
        .EventPause => {
            global_state.playdate_runtime.last_button.is_menu_shown = true;
        },
        else => {},
    }
    return 0;
}

fn updateAndRender(userdata: ?*anyopaque) callconv(.c) c_int {
    const state: *GlobalState = @ptrCast(@alignCast(userdata.?));
    state.game.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    state.playdate_runtime.playdate.system.drawFPS(1, 1);

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
