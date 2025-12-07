const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Change a target to an atacked enemy" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    const rat_left = try test_session.session.level.addEnemy(.sleeping, g.entities.rat(pp.movedTo(.left)));
    const rat_top = try test_session.session.level.addEnemy(.sleeping, g.entities.rat(pp.movedTo(.up)));
    errdefer std.debug.print("Left rat {d}; Top rat {d}\n", .{ rat_left.id, rat_top.id });

    // The initial game state:
    try test_session.tick();
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +•••••••••••r••••••••••••••••••#
        \\#•••└───┘••••••••••r•••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\                    ⇧Explore     Wait  ⇧
    , .whole_display);
    try std.testing.expectEqual(null, test_session.player.target());

    std.log.debug("Move the player to enemies", .{});
    try test_session.player.move(.up, 1);
    try std.testing.expectEqual(rat_left, test_session.player.target());

    std.log.debug("Hit another enemy", .{});
    try test_session.player.move(.up, 1);
    try std.testing.expectEqual(rat_top, test_session.player.target());
}

test "Lose target on moving away" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    try test_session.player.moveTo(.{ .row = 3, .col = 17 });
    try test_session.tick();
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\####•••••••••••••#     #••••••••••••••••
        \\####•••┌───┐•••••###+###•••••••••••┌───┐
        \\####•••│   +••••••••@••••••••••••••+   │
        \\####•••└───┘•••••••••••••••••••••••└───┘
        \\####•••┌───┐••••••••••••••••••••••••••••
        \\####•••│   +••••••••••••••••••••••••••••
        \\####•••└───┘••••••••••••••••••••••••••••
        \\~~~~~~~~~~~~~~~~~~~~~~│<│~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\    Closed door     ⇧Explore ��  Open  ⇧
    , .whole_display);
    const door = g.Entity{ .id = 24 };
    try std.testing.expectEqual(door, test_session.player.target());

    std.log.debug("Move the player away from the door", .{});
    try test_session.player.move(.down, 1);
    try std.testing.expectEqual(null, test_session.player.target());
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\####•••••••••••••#     #••••••••••••••••
        \\####•••┌───┐•••••###+###•••••••••••┌───┐
        \\####•••│   +•••••••••••••••••••••••+   │
        \\####•••└───┘••••••••@••••••••••••••└───┘
        \\####•••┌───┐••••••••••••••••••••••••••••
        \\####•••│   +••••••••••••••••••••••••••••
        \\####•••└───┘••••••••••••••••••••••••••••
        \\~~~~~~~~~~~~~~~~~~~~~~│<│~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\                    ⇧Explore ��  Wait  ⇧
    , .whole_display);
}
