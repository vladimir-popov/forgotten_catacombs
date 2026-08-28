const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");

test "Regeneration should increase health every N cycles" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const regeneration = test_session.session.registry.getUnsafe(test_session.player.id, c.Regeneration);
    errdefer std.debug.print("{any}\n", .{regeneration});

    const health = test_session.player.health();
    health.current_hp -= 10;
    const health_before = health.current_hp;

    // spend required number of cycles (waiting)
    for (0..regeneration.turns_to_increase) |_| {
        try test_session.pressButton(.a);
    }

    // then:
    try std.testing.expectEqual(health_before + 1, health.current_hp);
}

test "Hunger should decrease health every cycle" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const hunger = test_session.session.registry.getUnsafe(test_session.player.id, c.Hunger);
    errdefer std.debug.print("{any}\n", .{hunger});

    const health = test_session.player.health();
    errdefer std.debug.print("{any}\n", .{health});
    const health_before = health.current_hp;

    // spend required for hunger number of cycles (waiting)
    while (hunger.level() != .hunger) {
        try test_session.pressButton(.a);
    }

    // and few more for damage
    for (0..5) |_| {
        try test_session.pressButton(.a);
    }

    // then:
    try test_session.runtime.display.expectLooksLike(
        \\######################################29
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +••••••••••••••••••••••••••••••#
        \\#•••└───┘••••••••••••••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│@│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
        \\════════════════════════════════════════
        \\       Hungry       ⇧Explore ��  Wait  ⇧
    , .whole_display);
    try std.testing.expect(health.current_hp < health_before);
}

test "Poison should damaging every tick" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    try test_session.session.registry.set(test_session.player.id, c.Poison{ .damage = 10 });
    const health_before = test_session.player.health().current_hp;

    // apply poison once (waiting)
    try test_session.pressButton(.a);

    // then:
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
        \\════════════════════════════════════════
        \\      Poisoned      ⇧Explore ��  Wait  ⇧
    , .whole_display);
    try std.testing.expect(test_session.player.health().current_hp < health_before);
}
