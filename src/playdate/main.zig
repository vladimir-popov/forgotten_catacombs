const std = @import("std");
const api = @import("api.zig");
const g = @import("game");

const PlaydateRuntime = @import("PlaydateRuntime.zig");

const log = std.log.scoped(.playdate);

pub const std_options = std.Options{
    .log_level = .warn,
    .logFn = writeLog,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        // .{ .scope = .default, .level = .debug },
        .{ .scope = .stack, .level = .debug },
        .{ .scope = .playdate, .level = .info },
        // .{ .scope = .game, .level = .debug },
        // .{ .scope = .game_session, .level = .debug },
        // .{ .scope = .playdate_io, .level = .debug },
        // .{ .scope = .last_button, .level = .debug },
        // .{ .scope = .runtime, .level = .debug },
        // .{ .scope = .render, .level = .warn },
        // .{ .scope = .visibility, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .explore_mode, .level = .debug },
        // .{ .scope = .looking_around_mode, .level = .debug },
        // .{ .scope = .save_load_mode, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .cmd, .level = .debug },
        // .{ .scope = .events, .level = .debug },
        // .{ .scope = .actions, .level = .debug },
    },
};

var log_buffer: [128]u8 = undefined;

fn writeLog(
    comptime _: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = std.fmt.comptimePrint("({t}) ", .{scope});
    const msg = std.fmt.bufPrint(&log_buffer, prefix ++ format, args) catch |err|
        switch (err) {
            // Let's write as much as possible
            error.NoSpaceLeft => &log_buffer,
        };
    const end = @min(msg.len, log_buffer.len - 1);
    log_buffer[end] = 0;
    playdate_log_to_console(msg.ptr);
}

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    return_address: ?usize,
) noreturn {
    _ = error_return_trace;
    _ = return_address;
    const msg0 = std.fmt.bufPrint(&log_buffer, "{s}", .{msg}) catch |err|
        switch (err) {
            // Let's write as much as possible
            error.NoSpaceLeft => &log_buffer,
        };
    const end = @min(msg0.len, log_buffer.len - 1);
    log_buffer[end] = 0;
    playdate_error_to_console(msg0.ptr);
    @breakpoint();
    @trap();
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
            const seed = playdate.system.getCurrentTimeMilliseconds();
            global_state.game = g.Game.init(
                global_state.playdate_runtime.alloc,
                global_state.playdate_runtime.runtime(),
                seed,
            ) catch
                @panic("Error on creating game session");

            playdate.display.setRefreshRate(0);
            playdate.system.setUpdateCallback(updateAndRender, global_state);
            log.info("\nRun game with seed {d}\n", .{seed});
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
    // we get the first address on the stack here, this is why take the point on the pointer here
    state.playdate_runtime.stack_start = @intFromPtr(&state);
    state.game.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    state.playdate_runtime.playdate.system.drawFPS(1, 1);

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
