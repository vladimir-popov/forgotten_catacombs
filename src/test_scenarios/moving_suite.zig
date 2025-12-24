const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

fn setup(test_session: *TestSession) !void {
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
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
    , .game_area);
    try std.testing.expect(test_session.session.mode == .play);
    try std.testing.expect(test_session.session.mode.play.is_player_turn);
}

test "player's turn should be completed after moving on empty space" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    defer test_session.deinit();

    // when:
    try test_session.pressButton(.up);

    // then:
    try std.testing.expectEqual(false, test_session.session.mode.play.is_player_turn);
}

test "player's turn should NOT be completed after moving to a wall" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    defer test_session.deinit();

    // when:
    try test_session.pressButton(.right);

    // then:
    try std.testing.expectEqual(true, test_session.session.mode.play.is_player_turn);
}

test "the global turns counter should be incremented after player moved on empty space with normal speed" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    defer test_session.deinit();
    const initial_counter = test_session.session.spent_turns;

    // when:
    try test_session.pressButton(.up);

    // then:
    try std.testing.expectEqual(initial_counter + 1, test_session.session.spent_turns);
}

test "the global turns counter should NOT be incremented after player moved on empty space with x2 speed" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    defer test_session.deinit();
    // note, that x2 speed means /2 less points in turn!
    test_session.session.registry.getUnsafe(test_session.player.id, c.Speed).move_points = g.MOVE_POINTS_IN_TURN / 2;
    const initial_counter = test_session.session.spent_turns;

    // when:
    try test_session.pressButton(.up);

    // then:
    try std.testing.expectEqual(initial_counter, test_session.session.spent_turns);
}

test "the global turns counter should be incremented after player moved on empty space with x2 speed twice" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    errdefer test_session.printDisplay();
    defer test_session.deinit();
    // note, that x2 speed means /2 less points in turn!
    test_session.session.registry.getUnsafe(test_session.player.id, c.Speed).move_points = g.MOVE_POINTS_IN_TURN / 2;
    const initial_counter = test_session.session.spent_turns;

    // when:
    try test_session.pressButton(.up);
    try test_session.completeRound();
    try test_session.pressButton(.up);

    // then:
    try std.testing.expectEqual(initial_counter + 1, test_session.session.spent_turns);
}

test "the global turns counter should be incremented twice after player moved on empty space with normal speed / 2" {
    // given:
    var test_session: TestSession = undefined;
    try setup(&test_session);
    defer test_session.deinit();
    test_session.session.registry.getUnsafe(test_session.player.id, c.Speed).move_points = g.MOVE_POINTS_IN_TURN * 2;
    const initial_counter = test_session.session.spent_turns;

    // when:
    try test_session.pressButton(.up);

    // then:
    try std.testing.expectEqual(initial_counter + 2, test_session.session.spent_turns);
}
