const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

test "Player should be damaged on stepping in trap" {
    // prepare the game:
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    _ = try addTrapInFrontOfPlayer(&test_session);
    const health_before = test_session.player.health().current_hp;

    // move into the trap:
    try test_session.pressButton(.up);

    // then:
    const health_after = test_session.player.health().current_hp;
    try std.testing.expect(health_after < health_before);
}

test "A trap should not be removed when player leave it" {
    // prepare the game:
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    _ = try addTrapInFrontOfPlayer(&test_session);

    // move into the trap:
    try test_session.pressButton(.up);
    try test_session.completeRound();
    try test_session.runtime.display.expectLooksLike(
        \\•••
        \\•@•
        \\•••
    , .{ .region = .init(3, 19, 3, 3) });

    // move out from the trap:
    try test_session.pressButton(.up);
    try test_session.completeRound();

    // then:
    try test_session.runtime.display.expectLooksLike(
        \\•@•
        \\•^•
        \\•••
    , .{ .region = .init(3, 19, 3, 3) });
}

fn addTrapInFrontOfPlayer(test_session: *TestSession) !g.Entity {
    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const trap_entity = try test_session.session.level.addRandomTrap(prng.random(), pp);
    try test_session.session.journal.markTrapAsKnown(trap_entity);

    // The initial game state:
    try test_session.tick(.{});
    try test_session.runtime.display.expectLooksLike(
        \\••••••••••••••••••••••••••••••••••••••30
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\•••••••••••••••••••^••••••••••••••••••••
        \\•••••••••••••••••••@••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
    , .game_area);
    try test_session.runtime.display.expectLooksLike(
        \\•••
        \\•^•
        \\•@•
    , .{ .region = .init(3, 19, 3, 3) });
    try std.testing.expectEqual(null, test_session.player.target());
    return trap_entity;
}
