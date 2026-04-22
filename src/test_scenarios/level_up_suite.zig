const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

test "A notification should appear after killing an enemy and receiving enough exp for level up." {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const rat_id = try addRatAndExp(&test_session);

    // Hit the target
    const rat_health = test_session.session.registry.getUnsafe(rat_id, c.Health);
    const initial_health = rat_health.current_hp;
    while (rat_health.current_hp == initial_health) {
        try test_session.pressButton(.a);
    }
    // Skip a notification about experience
    try test_session.tick(.{ .count = 4, .duration_ms = 400 });

    // Check a notification
    try test_session.runtime.display.expectLooksLike(
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘•••••••Level up!••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    , .game_area_without_first_line);
}

test "Level up should become available after killing an enemy and receiving enough exp" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const rat_id = try addRatAndExp(&test_session);

    // Check that the Level up is not available
    try test_session.exploreMode();
    try test_session.runtime.display.expectLooksLike(
        \\        You           Cancel   Describe⇧
    , .info_bar);
    try test_session.pressButton(.a);
    try test_session.runtime.display.expectLooksLike(
        \\        You                     Close   
    , .info_bar);

    // Close description
    try test_session.pressButton(.a);
    // Cancel to return to the Play mode
    try test_session.pressButton(.b);
    try test_session.tick(.{ .count = 5 });
    try test_session.runtime.display.expectLooksLike(
        \\ r:|                ⇧Explore �� Attack ⇧
    , .info_bar);

    // Hit the target
    const rat_health = test_session.session.registry.getUnsafe(rat_id, c.Health);
    const initial_health = rat_health.current_hp;
    while (rat_health.current_hp == initial_health) {
        try test_session.pressButton(.a);
    }
    // Skip notifications
    try test_session.tick(.{ .duration_ms = 2000 });

    // Now the level up should be available
    try test_session.exploreMode();
    try test_session.runtime.display.expectLooksLike(
        \\        You           Cancel   Describe⇧
    , .info_bar);
    try test_session.pressButton(.a);
    try test_session.runtime.display.expectLooksLike(
        \\     Level up!       Up level   Close   
    , .info_bar);
}

/// Adds a rat with 1 hp to the level, and increase the player's exp to the value of one point less to get the
/// new level.
fn addRatAndExp(test_session: *TestSession) !g.Entity {
    // Prepare a game session:
    const player_exp: *c.Experience = test_session.player.experience();
    player_exp.experience += g.meta.experienceToNextLevel(player_exp.level) - 1;

    const pp = test_session.player.position().place.movedToNTimes(.up, 1);
    var rat: c.Components = g.entities.enemyAtPlace(.rat, pp);
    rat.health.?.current_hp = 1;
    const rat_id = try test_session.session.level.addEnemy(.sleeping, rat);

    // Updating quick actions
    try test_session.session.mode.play.updateQuickActions();
    // Redraw the info bar
    try test_session.tick(.{});
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘•••••••••••r••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\ r:|                ⇧Explore    Attack ⇧
    , .whole_display);
    try std.testing.expectEqual(rat_id, test_session.player.target());
    return rat_id;
}
