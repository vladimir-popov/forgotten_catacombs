const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");


test "Rendering initial inventory" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty();
    defer test_session.deinit();

    _ = try test_session.openInventory();

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║\ Pickaxe                     weapon  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$          Close     Choose ⇧
    );
}

test "Unequip torch" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty();
    defer test_session.deinit();

    var inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Torch");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║┌────────────────────────────────────┐║
        \\║│              Unequip               │║
        \\║│                Drop                │║
        \\║│              Describe              │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$          Close     Choose  
    );

    try options.choose("Unequip");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║\ Pickaxe                     weapon  ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$          Close     Choose ⇧
    );
}

test "Use torch as a weapon" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty();
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    var options = try inventory.chooseItemByName("Torch");
    try options.choose("Unequip");
    options = try inventory.chooseItemByName("Torch");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║┌────────────────────────────────────┐║
        \\║│           Use as a light           │║
        \\║│          Use as a weapon           │║
        \\║│                Drop                │║
        \\║│              Describe              │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$          Close     Choose  
    );
    try options.choose("Use as a weapon");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║\ Pickaxe                             ║
        \\║¡ Torch                       weapon  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        200$          Close     Choose ⇧
    );
}

test "Drink healing potion" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty();
    defer test_session.deinit();

    test_session.player.health().current = 5;
    const potion = try test_session.player.addToInventory(g.entities.HealingPotion);
    const inventory = try test_session.openInventory();
    const options = try inventory.chooseItemById(potion);
    try options.choose("Drink");

    try std.testing.expect(test_session.player.health().current > 5);
}
