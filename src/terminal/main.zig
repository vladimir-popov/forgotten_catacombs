const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const Args = @import("Args.zig");
const TtyRuntime = @import("TtyRuntime.zig");
const Logger = @import("Logger.zig");

pub const std_options: std.Options = .{
    .logFn = Logger.writeLog,
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .default, .level = .debug },
        .{ .scope = .render, .level = .warn },
        // .{ .scope = .tty_runtime, .level = .debug },
        // .{ .scope = .visibility, .level = .debug },
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .game, .level = .debug },
        // .{ .scope = .game_session, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .looking_around_mode, .level = .debug },
        // .{ .scope = .levels, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .cmd, .level = .debug },
        // .{ .scope = .level_map, .level = .debug },
        // .{ .scope = .events, .level = .debug },
        // .{ .scope = .action_system, .level = .debug },
    },
};

const log = std.log.scoped(.main);

pub fn panic(
    msg: []const u8,
    error_return_trace: ?*std.builtin.StackTrace,
    return_address: ?usize,
) noreturn {
    TtyRuntime.disableGameMode() catch unreachable;
    std.debug.panicImpl(error_return_trace, return_address, msg);
}

pub fn main() !void {
    const seed = try Args.int(u64, "seed") orelse std.crypto.random.int(u64);
    log.info("\n====================\nSeed of the game is {d}\n====================", .{seed});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    const use_cheats = Args.flag("devmode");

    var runtime = try TtyRuntime.TtyRuntime(g.DISPLAY_ROWS + 2, g.DISPLAY_COLS + 2)
        .init(alloc, true, true, use_cheats);
    defer runtime.deinit();
    if (use_cheats) {
        log.warn("The Developer is in the room!", .{});
        if (Args.str("cheat")) |value| {
            runtime.cheat = g.Cheat.parse(value);
        }
    }
    const game = try g.Game.create(alloc, runtime.runtime(), seed);
    defer game.destroy();
    runtime.run(game) catch |e| {
        std.debug.panic("Fatal error {any}", .{e});
    };
}
