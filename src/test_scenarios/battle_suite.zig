const std = @import("std");
const g = @import("game");
const c  = g.components;
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
    var options = try inventory.chooseItemById(arrows);
    try options.choose("Put to quiver");
    try std.testing.expectEqual(arrows, test_session.player.equipment().ammunition);

    options = try inventory.chooseItemById(bow);
    try options.choose("Use as a weapon");
    try std.testing.expectEqual(bow, test_session.player.equipment().weapon);
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
    try test_session.pressButton(.a);
    try std.testing.expectEqual(rat, test_session.player.target());

    // Hit the target
    const rat_health = test_session.session.registry.getUnsafe(rat, c.Health);
    const initial_health = rat_health.current;
    while (rat_health.current == initial_health) {
        try test_session.pressButton(.a);
    }
}
