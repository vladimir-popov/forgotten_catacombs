const std = @import("std");
const game = @import("game");
const tty = @import("tty.zig");

const TtyRuntime = @import("TtyRuntime.zig");
const Logger = @import("Logger.zig");

pub const std_options = .{
    .logFn = Logger.writeLog,
};

const log = std.log.scoped(.main);

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const seed = if (args.next()) |arg|
        try std.fmt.parseInt(u64, arg, 10)
    else
        std.crypto.random.int(u64);
    log.info("Seed of the game is {d}", .{seed});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var prng = std.Random.DefaultPrng.init(seed);
    var runtime = try TtyRuntime.init(alloc, prng.random(), true);
    defer runtime.deinit();
    var gm = try game.Game.init(runtime.any());
    defer gm.deinit();
    try runtime.run(&gm);
}

test {
    std.testing.refAllDecls(@This());
}
