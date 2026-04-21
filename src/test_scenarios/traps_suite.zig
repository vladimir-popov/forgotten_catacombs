const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

const trap_region = g.primitives.Region.init(3, 19, 3, 3);

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
    const trap_entity = try addTrapInFrontOfPlayer(&test_session);

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
    try std.testing.expectEqual(trap_entity, test_session.player.target());
}

test "Should not notice the trap without moving or waiting" {
    // prepare the game with invisible trap:
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    _ = try addTrapInFrontOfPlayer(&test_session);

    for (0..30) |iteration| {
        // when:
        try test_session.tick(.{});
        //then:
        test_session.runtime.display.expectLooksLike(
            \\•••
            \\•••
            \\•@•
        , .{ .region = trap_region }) catch |err| {
            std.log.err("The trap was noticed on {d} iteration", .{iteration});
            return err;
        };
        try std.testing.expectEqual(null, test_session.player.target());
    }
}

test "Should notice the trap moving around" {
    // prepare the game with invisible trap:
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    const trap_entity = try addTrapInFrontOfPlayer(&test_session);
    _ = test_session.session.journal.known_entities.remove(trap_entity);
    test_session.session.registry.getUnsafe(trap_entity, c.Trap).power = 3;

    // Initially, the trap should not be visible
    try test_session.runtime.display.expectLooksLike(
        \\•••
        \\•••
        \\•@•
    , .{ .region = trap_region });

    var is_left_btn = true;
    for (0..50) |_| {
        // when:
        try test_session.pressButton(if (is_left_btn) .left else .right);
        try test_session.completeRound();
        is_left_btn = !is_left_btn;
        if (try test_session.runtime.display.isEqualToString("•••••••••••••••••••^••••••••••••••••••••", .{ .line = 4 }))
            break
        else
            try std.testing.expectEqual(null, test_session.player.target());
    }
    // finally the trap must become visible:
    try test_session.runtime.display.expectLooksLike("•••••••••••••••••••^••••••••••••••••••••", .{ .line = 4 });
}

fn addTrapInFrontOfPlayer(test_session: *TestSession) !g.Entity {
    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const trap_entity = try test_session.session.level.addRandomTrap(prng.random(), pp, 0);

    // The initial game state:
    try test_session.tick(.{});

    // Checks only for debug. It shows how the level and the region with trap should look:
    if (false) {
        try test_session.session.journal.markTrapAsKnown(trap_entity);
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
        , .{ .region = trap_region });
    }
    try std.testing.expectEqual(null, test_session.player.target());
    return trap_entity;
}
