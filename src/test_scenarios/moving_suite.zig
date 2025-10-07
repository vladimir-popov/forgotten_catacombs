const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

fn setup(test_session: *TestSession) !void {
    try test_session.initEmpty(std.testing.allocator);
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
