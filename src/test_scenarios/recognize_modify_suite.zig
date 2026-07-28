const std = @import("std");
const g = @import("game");
const c = g.components;
const Options = @import("utils/Options.zig");
const RecognizeModify = @import("utils/RecognizeModify.zig");
const TestSession = @import("utils/TestSession.zig");

test "Init near the scientist" {
    var test_session: TestSession = undefined;
    _, const unknown_item_id, _ = try initNearScientistWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try std.testing.expect(!test_session.session.journal.isKnown(unknown_item_id));
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Recognize     ║     Modify       ║
        \\║                   ╚══════════════════║
        \\║¿ A yellow potion                 22$ ║
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
    const recognize_modify, const unknown_item_id, _ = try initNearScientistWithMoney(&test_session, 1000);
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
        \\ Your money:  978$              Close   
    , .whole_display);
}

test "Recognize an unknown item when NOT enough money" {
    var test_session: TestSession = undefined;
    const recognize_modify, const unknown_item_id, _ = try initNearScientistWithMoney(&test_session, 0);
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

test "Modification should be applicable only to weapons or armor" {
    var test_session: TestSession = undefined;
    const recognize_modify, _, _ = try initNearScientistWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try recognize_modify.chooseModifyTab();
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Recognize    ║      Modify       ║
        \\║══════════════════╝                   ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money: 1000$    Close     Choose ⇧
    , .whole_display);
}

test "Modify an item somehow when enough money" {
    var test_session: TestSession = undefined;
    const recognize_modify, _, const known_weapon_id = try initNearScientistWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try recognize_modify.chooseModifyTab();
    try std.testing.expect(!test_session.session.registry.has(known_weapon_id, c.Improvements));
    try std.testing.expect(!test_session.session.registry.has(known_weapon_id, c.Breakages));

    const options = try recognize_modify.chooseItemById(known_weapon_id);
    try options.choose("Modify");
    try options.choose("Somehow");

    try std.testing.expect(!test_session.session.journal.isKnown(known_weapon_id));
    try std.testing.expect(test_session.session.registry.has(known_weapon_id, c.Improvements) or
        test_session.session.registry.has(known_weapon_id, c.Breakages));
    try recognize_modify.chooseRecognizeTab();
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Recognize     ║     Modify       ║
        \\║                   ╚══════════════════║
        \\║\ Pickaxe                         11$ ║
        \\║¿ A yellow potion                 22$ ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money:  992$    Close  �� Choose ⇧
    , .whole_display);
}

test "Modify an item when NOT enough money" {
    var test_session: TestSession = undefined;
    const recognize_modify, _, const known_weapon_id = try initNearScientistWithMoney(&test_session, 0);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try recognize_modify.chooseModifyTab();
    const options = try recognize_modify.chooseItemById(known_weapon_id);
    try options.choose("Modify");
    try options.choose("Somehow");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Recognize    ║      Modify       ║
        \\║══════════════════╝                   ║
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

/// Initializes a test session with the player on the start level near the scientist.
/// Set puts the money to the player's wallet, and adds a healing potion as unknown to the player's inventory.
/// Returns the new test session, id of the healing potion, and id of the player's weapon.
fn initNearScientistWithMoney(test_session: *TestSession, money: u16) !struct { RecognizeModify, g.Entity, g.Entity } {
    std.testing.random_seed = 100500;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    const known_weapon_id = test_session.player.equipment().weapon.?;
    const unknown_item = g.entities.presets.Potions.get(.healing_potion);
    const unknown_item_id = try test_session.session.registry.addNewEntity(unknown_item);
    try test_session.player.inventory().items.add(unknown_item_id);
    test_session.player.position().place = g.dungeon.FirstLocation.scientist_place.movedTo(.right);
    test_session.player.wallet().money = money;
    try test_session.pressButton(.left);
    return .{ .{ .test_session = test_session }, unknown_item_id, known_weapon_id };
}
