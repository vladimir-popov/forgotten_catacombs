const std = @import("std");
const g = @import("game");

const Args = @import("Args.zig");
const Logger = @import("Logger.zig");
// exported for tests
pub const tty = @import("tty.zig");
pub const TtyRuntime = @import("TtyRuntime.zig");

pub const std_options: std.Options = .{
    .logFn = Logger.writeLog,
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .default, .level = .debug },
        .{ .scope = .cheats, .level = .debug },
        .{ .scope = .game_session, .level = .debug },
        .{ .scope = .actions, .level = .debug },
        // .{ .scope = .registry, .level = .debug },
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .cave, .level = .debug },
        // .{ .scope = .cmd, .level = .debug },
        // .{ .scope = .events, .level = .debug },
        // .{ .scope = .game, .level = .debug },
        .{ .scope = .inventory_mode, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .load_level_mode, .level = .debug },
        // .{ .scope = .looking_around_mode, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .render, .level = .warn },
        // .{ .scope = .save_load_mode, .level = .debug },
        // .{ .scope = .visibility, .level = .debug },
        // .{ .scope = .windows, .level = .debug },
    },
};

const log = std.log.scoped(.main);

pub const panic = std.debug.FullPanic(handlePanic);

pub fn handlePanic(
    msg: []const u8,
    first_trace_addr: ?usize,
) noreturn {
    TtyRuntime.disableGameMode() catch unreachable;
    std.debug.defaultPanic(msg, first_trace_addr);
}

pub fn main() !void {
    const seed = try Args.int(u64, "seed") orelse std.crypto.random.int(u64);
    log.info("========================================\nSeed of the game is {d}\n========================================", .{seed});

    var gpa = std.heap.DebugAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    const use_cheats = Args.flag("devmode");
    const use_mouse = Args.flag("mouse");

    var runtime = try TtyRuntime.TtyRuntime(g.DISPLAY_ROWS + 2, g.DISPLAY_COLS + 2)
        .init(alloc, true, true, use_cheats, use_mouse);
    defer runtime.deinit();
    if (use_cheats) {
        log.warn("The Developer is in the room!", .{});
        if (Args.str("cheat")) |value| {
            runtime.cheat = g.Cheat.parse(value);
        }
    }
    var game = try alloc.create(g.Game);
    defer alloc.destroy(game);

    try game.init(alloc, runtime.runtime(), seed);
    defer game.deinit();

    try runtime.run(game);
}
