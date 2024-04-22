const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");

const Runtime = @import("Runtime.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var runtime = try Runtime.init(alloc, std.crypto.random, &arena);
    defer runtime.deinit();
    var game = try gm.ForgottenCatacomb.init(runtime.any());
    defer game.deinit();

    try runtime.run(&game);
}

test {
    std.testing.refAllDecls(@This());
}
