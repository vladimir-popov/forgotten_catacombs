const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

test "Show a notification from the center" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    try test_session.session.notify(.{ .exp = 100 });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\••••••••••••••••••••••••••••••••••••••30
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\•••••••••••••••+100 EXP•••••••••••••••••
        \\•••••••••••••••••••@••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
    , .game_area);
}

test "Show a notification from the top left corner" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    test_session.player.position().place = .init(1, 1);
    try test_session.session.notify(.{ .exp = 100 });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\@•••••••••••••••••••••••••••••••••••••30
        \\+100 EXP••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
    , .game_area);
}

test "Show a notification near the left border" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    test_session.player.position().place = .init(2, 2);
    try test_session.session.notify(.{ .exp = 100 });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\+100 EXP••••••••••••••••••••••••••••••30
        \\•@••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
    , .game_area);
}

test "Show a notification from the bottom right corner" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    test_session.player.position().place = .init(10, 40);
    try test_session.session.notify(.{ .exp = 100 });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\••••••••••••••••••••••••••••••••••••••30
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••+100 EXP
        \\•••••••••••••••••••••••••••••••••••••••@
    , .game_area);
}

test "Show a notification near the right border" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    test_session.player.position().place = .init(10, 39);
    try test_session.session.notify(.{ .exp = 100 });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\••••••••••••••••••••••••••••••••••••••30
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••+100 EXP
        \\••••••••••••••••••••••••••••••••••••••@•
    , .game_area);
}

test "Show a notification near an enemy" {
    var test_session: TestSession = undefined;
    try test_session.initWithTestArea(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const pp = test_session.player.position().place.movedTo(.up).movedTo(.left);
    const rat = try test_session.session.level.addEnemy(.sleeping, g.entities.Enemies.atPlace(.rat, pp));
    test_session.session.mode.play.target = rat;

    try test_session.session.notify(.{ .hit = .{ .target = rat, .damage = 5, .damage_type = .physical } });
    try test_session.tick();
    try test_session.tick();

    try test_session.runtime.display.expectLooksLike(
        \\••••••••••••••••••••••••••••••••••••••30
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••r•••••••••••••••••••••
        \\•••••••••••••••••••@••••••••••••••••••••
        \\••••••••••••••••5 hit•••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
        \\••••••••••••••••••••••••••••••••••••••••
    , .game_area);
}
