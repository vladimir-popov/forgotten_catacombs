const std = @import("std");
const trm = @import("terminal/Terminal.zig");
const ecs = @import("ecs.zig");

pub fn main() !void {
    const terminal = try trm.Terminal.init();
    defer terminal.deinit();

    while (true) {
        const kb = try terminal.readPressedKey();
        std.debug.print("{any}", .{kb.code[0..kb.len]});
    }
}
