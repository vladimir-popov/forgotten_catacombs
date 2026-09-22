//!## Run game
//!
//! 1. eventHandler(pd, .EventInit, 0);
//! 2. updateAndRender().
//!
//!## Frame Run Loop
//!```
//! [Frame start]
//! 1. Button callbacks (`LastButton.handleEvent`)
//!    Once for each press/release event in the queue;
//! 2. Game logic and rendering
//!    `updateAndRender()`;
//! 3. Playdate OS refreshes the display using the framebuffer
//!    if updateAndRender returned 1;
//! [Wait for the next frame / update opportunity]
//!```
//!## System Menu
//!
//!### Open
//!
//! 1. eventHandler(pd, .EventPause, 0);
//! 2. Stop calling the updateAndRender.
//!
//!### Handle menu / Close
//!
//! 1. Handle an item callback;
//! 2. eventHandler(pd, .EventResume, 0);
//! 3. Button callbacks with all pressed buttons during navigate the menu;
//! 4. updateAndRender().
//!
const std = @import("std");
const api = @import("api.zig");
const g = @import("game");

const LastButton = @import("LastButton.zig");
const PlaydateRuntime = @import("PlaydateRuntime.zig");

const log = std.log.scoped(.playdate);

pub const std_options = std.Options{
    .log_level = .warn,
    .logFn = writeLog,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        // .{ .scope = .default, .level = .debug },
        // .{ .scope = .stack, .level = .debug },
        // .{ .scope = .game, .level = .info },
        // .{ .scope = .playdate, .level = .debug },
        // .{ .scope = .last_button, .level = .debug },
    },
};

var log_buffer: [256]u8 = undefined;

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
            playdate.system.setButtonCallback(LastButton.handleEvent, &global_state.playdate_runtime.last_button, 5);
            global_state.game = g.Game.init(
                global_state.playdate_runtime.alloc,
                global_state.playdate_runtime.runtime(),
                null,
            ) catch
                @panic("Error on creating game session");

            playdate.display.setRefreshRate(0);
            playdate.system.setUpdateCallback(updateAndRender, global_state);
        },
        .EventPause => {
            log.debug("EventPause", .{});
            global_state.playdate_runtime.is_menu_shown = true;
        },
        else => {},
    }
    return 0;
}

fn updateAndRender(userdata: ?*anyopaque) callconv(.c) c_int {
    const state: *GlobalState = @ptrCast(@alignCast(userdata.?));

    // If this callback is invoked then the menu is closed.
    // We have skip one button handler to ignore buttons pressed when the menu was opened.
    state.playdate_runtime.is_menu_shown = false;

    // we get the first address on the stack here, this is why take the point on the pointer here
    state.playdate_runtime.stack_start = @intFromPtr(&state);
    state.game.tick() catch |err|
        std.debug.panic("Error {any} on game tick", .{err});

    state.playdate_runtime.playdate.system.drawFPS(1, 1);

    //returning 1 signals to the OS to draw the frame.
    return 1;
}
