const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

test "Shoot at the target" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const rat_id = try initFirstLevelWithRat(&test_session);
    _ = try equipBowAndArrows(&test_session);

    // Take aim at a rat
    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try test_session.pressButton(.a);
    try std.testing.expectEqual(rat_id, test_session.player.target());

    // Hit the target
    const rat_health = test_session.session.registry.getUnsafe(rat_id, c.Health);
    const initial_health = rat_health.current;
    while (rat_health.current == initial_health) {
        try test_session.pressButton(.a);
    }
}

test "The arrows entity should be removed when the last arrow was issued" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const rat_id = try initFirstLevelWithRat(&test_session);
    const bow_and_arrows = try equipBowAndArrows(&test_session);
    test_session.session.registry.getUnsafe(bow_and_arrows[1], c.Ammunition).amount = 1;

    // Take aim at a rat
    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try test_session.pressButton(.a);
    try std.testing.expectEqual(rat_id, test_session.player.target());

    // Hit the target
    try test_session.pressButton(.a);

    // The arrows should be removed from the registry,
    try std.testing.expect(!test_session.session.registry.contains(bow_and_arrows[1]));
    // ...from the equipment
    try std.testing.expect(test_session.player.equipment().ammunition == null);
    // ...and from the inventory.
    try std.testing.expect(!test_session.player.inventory().items.contains(bow_and_arrows[1]));
}

fn initFirstLevelWithRat(test_session: *TestSession) !g.Entity {
    // Prepare a game session:
    const pp = test_session.player.position().place.movedToNTimes(.up, 4);
    const rat = try test_session.session.level.addEnemy(.sleeping, g.entities.enemyAtPlace(.rat, pp));

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
    return rat;
}

fn equipBowAndArrows(test_session: *TestSession) !struct { g.Entity, g.Entity } {
    const inventory = try test_session.openInventory();
    const arrows_id = try inventory.add(g.entities.presets.Items.get(.arrows));
    const bow_id = try inventory.add(g.entities.presets.Items.get(.short_bow));
    var options = try inventory.chooseItemById(arrows_id);
    try options.choose("Put to quiver");
    try std.testing.expectEqual(arrows_id, test_session.player.equipment().ammunition);

    options = try inventory.chooseItemById(bow_id);
    try options.choose("Use as a weapon");
    try std.testing.expectEqual(bow_id, test_session.player.equipment().weapon);
    try inventory.close();

    return .{ bow_id, arrows_id };
}
