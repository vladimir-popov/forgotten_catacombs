const std = @import("std");
const Frame = @import("utils/Frame.zig");
const TestSession = @import("utils/TestSession.zig");

test {
    _ = @import("battle_suite.zig");
    _ = @import("description_suite.zig");
    _ = @import("inventory_suite.zig");
    _ = @import("moving_suite.zig");
    _ = @import("notifications_suite.zig");
    _ = @import("recognize_modify_suite.zig");
    _ = @import("save_load_suite.zig");
    _ = @import("trading_suite.zig");
    _ = @import("update_target_suite.zig");
}

test "Hello world!" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
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
    , .whole_display);
}

test {
    std.testing.refAllDecls(@This());
}
