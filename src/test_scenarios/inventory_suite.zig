const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Rendering initial inventory" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    _ = try test_session.openInventory();

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Unequip torch" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
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
    , .game_area);

    try options.choose("Unequip");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Use torch as a weapon" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
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
    , .game_area);
    try options.choose("Use as a weapon");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                       weapon  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Put arrows to quiver" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const arrows = try inventory.add(g.entities.presets.Items.get(.arrows));
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║- Arrows 10                           ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    var options = try inventory.chooseItemById(arrows);
    try options.choose("Put to quiver");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║- Arrows 10                     ammo  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Drink a healing potion" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    test_session.player.health().current = 5;
    var inventory = try test_session.openInventory();
    const potion = try inventory.add(g.entities.presets.Items.get(.healing_potion));
    const options = try inventory.chooseItemById(potion);
    try options.choose("Drink");
    try std.testing.expect(inventory.isClosed());

    try std.testing.expect(!test_session.session.registry.contains(potion));
    try std.testing.expect(!test_session.player.inventory().items.contains(potion));
    try std.testing.expect(test_session.player.health().current > 5);
    try std.testing.expect(test_session.session.journal.known_potions.contains(.healing_potion));
}
