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

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var runtime = try Runtime.init(alloc, std.crypto.random, &arena);
    defer runtime.deinit();
    var universe = try game.createUniverse(runtime.any());
    defer universe.destroy();

    try runtime.run(&universe);
}

test {
    std.testing.refAllDecls(@This());
}
