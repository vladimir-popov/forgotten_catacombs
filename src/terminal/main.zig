const std = @import("std");
const game = @import("game");
const tty = @import("tty.zig");

const Runtime = @import("Runtime.zig");
const Logger = @import("Logger.zig");

pub const std_options = .{
    .logFn = Logger.writeLog,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var runtime = try Runtime.init(alloc, std.crypto.random, true);
    defer runtime.deinit();
    const session = try game.GameSession.create(runtime.any());
    defer session.destroy();
    try runtime.run(session);
}

test {
    std.testing.refAllDecls(@This());
}
