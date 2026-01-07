const std = @import("std");
const g = @import("game");
const c = g.components;
const Options = @import("utils/Options.zig");
const RecognizeModify = @import("utils/RecognizeModify.zig");
const TestSession = @import("utils/TestSession.zig");

test "Init near the scientist" {
    var test_session: TestSession = undefined;
    _, const unknown_item_id = try initNearScientistWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try std.testing.expect(!test_session.session.journal.isKnown(unknown_item_id));
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Recognize     ║     Modify       ║
        \\║                   ╚══════════════════║
        \\║¿ A green potion                 100$ ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money: 1000$    Close     Choose ⇧
    , .whole_display);
}

test "Recognize an unknown item when enough money" {
    var test_session: TestSession = undefined;
    const recognize_modify, const unknown_item_id = try initNearScientistWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const options = try recognize_modify.chooseItemById(unknown_item_id);
    try options.choose("Recognize");

    try std.testing.expect(test_session.session.journal.isKnown(unknown_item_id));
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Recognize     ║     Modify       ║
        \\║                   ╚══════════════════║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money:  900$              Close   
    , .whole_display);
}

test "Recognize an unknown item when NOT enough money" {
    var test_session: TestSession = undefined;
    const recognize_modify, const unknown_item_id = try initNearScientistWithMoney(&test_session, 0);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const options = try recognize_modify.chooseItemById(unknown_item_id);
    try options.choose("Recognize");

    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Recognize     ║     Modify       ║
        \\║                   ╚══════════════════║
        \\║┌────────────────────────────────────┐║
        \\║│          You have not enough       │║
        \\║│                 money.             │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money:    0$              Close   
    , .whole_display);
}

fn initNearScientistWithMoney(test_session: *TestSession, money: u16) !struct { RecognizeModify, g.Entity } {
    std.testing.random_seed = 100500;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    const unknown_item = g.presets.Items.fields.get(.healing_potion).*;
    const unknown_item_id = try test_session.session.registry.addNewEntity(unknown_item);
    try test_session.player.inventory().items.add(unknown_item_id);
    test_session.player.position().place = g.dungeon.FirstLocation.scientist_place.movedTo(.right);
    test_session.player.wallet().money = money;
    try test_session.pressButton(.left);
    return .{ .{ .test_session = test_session }, unknown_item_id };
}
