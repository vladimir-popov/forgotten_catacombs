const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Shoot at the target" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    const pp = test_session.player.position().place.movedToNTimes(.up, 4);
    const rat = try test_session.session.level.addEnemy(.sleeping, g.entities.rat(pp));

    // Equip a bow with arrows
    const inventory = try test_session.openInventory();
    const arrows = try inventory.add(g.presets.Items.values.get(.arrows).*);
    const bow = try inventory.add(g.presets.Items.values.get(.short_bow).*);
    try inventory.chooseItemById(arrows);
    try inventory.chooseItemById(bow);
    try inventory.close();

    // The initial game state:
    try test_session.tick();
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••r•••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘••••••••••••••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\                    ⇧Explore     Wait  ⇧
    , .whole_display);
    try std.testing.expectEqual(null, test_session.player.target());

    // Take aim at a rat
    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try std.testing.expectEqual(rat, test_session.player.target());
    try test_session.pressButton(.a);
}

