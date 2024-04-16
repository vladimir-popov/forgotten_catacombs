const std = @import("std");
const gm = @import("game");
const tty = @import("tty.zig");
const utf8 = @import("utf8");

const Environment = @import("Environment.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        const deinit_status = gpa.deinit();
        //fail test; can't try in defer as defer is executed after we return
        if (deinit_status == .leak) @panic("MEMORY LEAK DETECTED!");
    }
    var env = try Environment.init(30, 30, alloc);
    defer env.deinit();
    var game = gm.ForgottenCatacomb(Environment).init(env.runtime(), alloc);
    defer game.deinit();

    const exit = tty.Keyboard.Button{ .control = tty.Keyboard.ControlButton.ESC };
    while (!tty.Keyboard.isKeyPressed(exit)) {
        game.tick();
    }
}
