const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");

const Runtime = @import("Runtime.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("MEMORY LEAK DETECTED!");
    }
    var arena = std.heap.ArenaAllocator.init(alloc);
    var runtime = try Runtime.init(&arena, 30, 30);
    defer runtime.deinit();
    var game = try gm.ForgottenCatacomb.init(alloc, runtime.any());
    defer game.deinit();

    try runtime.run(&game);
}

test {
    std.testing.refAllDecls(@This());
}
