const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Describe a torch in devmode" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    test_session.runtime.is_dev_mode = true;
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Torch");
    try options.choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║┌───────────────Torch────────────────┐║
        \\║│ Id: 3                              │║
        \\║│ Damage: blunt 2-3                  │║
        \\║│ Effect: burning 1-1                │║
        \\║│ Radius of light: 5                 │║
        \\║│ Weight: 20                         │║
        \\║│------------------------------------│║
        \\║└────────────────────────────────────┘║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$                    Close   
    );
}
