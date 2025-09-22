const std = @import("std");
const Frame = @import("utils/Frame.zig");
const TestSession = @import("utils/TestSession.zig");

test {
    _ = @import("description.zig");
    _ = @import("inventory.zig");
    _ = @import("save_load.zig");
    _ = @import("update_target.zig");
}

test "Hello world!" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
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
