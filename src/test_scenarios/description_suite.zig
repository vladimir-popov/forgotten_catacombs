const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Describe an item" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Torch");
    try options.choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║┌───────────────Torch────────────────┐║
        \\║│Wooden handle, cloth wrap, burning ▒│║
        \\║│flame. Lasts until the fire dies.  ░│║
        \\║│                                   ░│║
        \\║│Damage: blunt 2-3                  ░│║
        \\║│Effect: burning 1-1                ░│║
        \\║│Radius of light: 5                 ░│║
        \\║└────────────────────────────────────┘║
        \\╚══════════════════════════════════════╝
    , .game_area);
}
