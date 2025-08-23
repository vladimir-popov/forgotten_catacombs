const std = @import("std");
const Frame = @import("utils/Frame.zig");
const TestSession = @import("utils/TestSession.zig");
const PotionsTest = @import("PotionsTest.zig");

pub fn main() !void {}

test "Hello world!" {
    var tmp_dir = std.testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator, tmp_dir.dir);
    defer test_session.deinit();

    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘••••••••••••••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\                    ⇧Explore     Wait  ⇧
    );
}

test {
    std.testing.refAllDecls(@This());
}
