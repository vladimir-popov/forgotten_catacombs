const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");

const TtyRuntime = @import("TtyRuntime.zig");
const Logger = @import("Logger.zig");

pub const std_options = .{
    .logFn = Logger.writeLog,
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
    var args = std.process.args();
    _ = args.next();
    const seed = if (args.next()) |arg|
        try std.fmt.parseInt(u64, arg, 10)
    else
        std.crypto.random.int(u64);
    log.info("Seed of the game is {d}\n====================", .{seed});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var runtime = try TtyRuntime.init(alloc, true);
    defer runtime.deinit();
    var game = try gm.Game.init(runtime.any(), seed);
    defer game.deinit();
    try runtime.run(&game);
}

test {
    std.testing.refAllDecls(@This());
}
