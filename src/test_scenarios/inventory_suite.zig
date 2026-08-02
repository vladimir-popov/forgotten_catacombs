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

test "Trying to unequip a broken weapon" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    const pickaxe_id = test_session.player.equipment().weapon.?;
    try std.testing.expect(try g.meta.breakItem(&test_session.session.registry, prng.random(), pickaxe_id, null));

    var inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Pickaxe");
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
        \\┌────────────────Oops!─────────────────┐
        \\│ Looks like it is broken and stuck.   │
        \\│ You will need to repair  it first.   │
        \\└──────────────────────────────────────┘
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    try test_session.pressButton(.a);
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
    , .game_area);
}

test "Drop an item" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    var inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Torch");
    try options.choose("Drop");
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Inventory     ║      Drop        ║
        \\║                   ╚══════════════════║
        \\║/ Pickaxe                     weapon  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
    try test_session.pressButton(.right);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Drop all items" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    var inventory = try test_session.openInventory();
    while (!inventory.isInvetoryEmpty()) {
        const options = try inventory.chooseItemByIndex(0);
        try options.choose("Drop");
    }
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Inventory     ║      Drop        ║
        \\║                   ╚══════════════════║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Pickup an item" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    // Drop:
    var inventory = try test_session.openInventory();
    var options = try inventory.chooseItemByName("Pickaxe");
    try options.choose("Drop");
    try test_session.pressButton(.right);
    // Pickup:
    options = try inventory.chooseItemByName("Pickaxe");
    try options.choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Pickup a single item from a pile" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    // Drop everything from the inventory:
    var inventory = try test_session.openInventory();
    while (!inventory.isInvetoryEmpty()) {
        const options = try inventory.chooseItemByIndex(0);
        try options.choose("Drop");
    }
    try test_session.pressButton(.right);
    // Pickup:
    const options = try inventory.chooseItemByIndex(0);
    try options.choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
    , .{ .region = .init(1, 1, 3, 40) });
}

test "Pickup all items from a pile" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    // Drop everything from the inventory:
    var inventory = try test_session.openInventory();
    while (!inventory.isInvetoryEmpty()) {
        const options = try inventory.chooseItemByIndex(0);
        try options.choose("Drop");
    }
    try test_session.pressButton(.right);
    // Pickup everything back:
    while (!inventory.isDropEmpty()) {
        const options = try inventory.chooseItemByIndex(0);
        try options.choose("Take");
    }
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
    , .{ .region = .init(1, 1, 3, 40) });
}

test "Pickup a gold pile" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Add a gold pile under the player:
    const pile_id = try test_session.session.registry.addNewEntity(g.entities.goldPile(42));
    // we expect that the gold pile is a single item on the place:
    try std.testing.expectEqual(
        null,
        try test_session.session.level.addItemAtPlace(pile_id, test_session.player.position().place),
    );

    // Open inventory
    var inventory = try test_session.openInventory();
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Inventory     ║      Drop        ║
        \\║                   ╚══════════════════║
        \\║/ Pickaxe                     weapon  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        107$          Close  �� Choose ⇧
    , .whole_display);

    // Switch to the Drop Tab:
    try test_session.pressButton(.right);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
        \\║$ Gold 42                             ║
    , .{ .region = .init(1, 1, 4, 40) });

    // Pickup the gold:
    const options = try inventory.chooseItemByIndex(0);
    try options.choose("Take");
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
        \\════════════════════════════════════════
        \\        149$          Close  �� Choose ⇧
    , .whole_display);

    // The gold pile should not exists anywhere:
    try std.testing.expect(
        !test_session.session.mode.inventory.inventory.items.contains(pile_id),
    );
    try std.testing.expect(
        !test_session.session.registry.contains(pile_id),
    );
}

test "Pickup gold from a pile of items" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    errdefer test_session.printDisplay();
    defer test_session.deinit();

    // Add a gold pile under the player:
    const gold_id = try test_session.session.registry.addNewEntity(g.entities.goldPile(42));
    _ = try test_session.session.level.addItemAtPlace(gold_id, test_session.player.position().place);

    // Drop everything from the inventory:
    var inventory = try test_session.openInventory();
    while (!inventory.isInvetoryEmpty()) {
        const options = try inventory.chooseItemByIndex(0);
        try options.choose("Drop");
    }

    // Switch to the Drop Tab:
    try test_session.pressButton(.right);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
        \\║/ Pickaxe                             ║
        \\║$ Gold 42                             ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        107$          Close  �� Choose ⇧
    , .whole_display);

    // Pickup the gold:
    const options = try inventory.chooseItemByName("Gold");
    try options.choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                               ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        149$          Close  �� Choose ⇧
    , .whole_display);

    // Switch back to the Inventory Tab:
    try test_session.pressButton(.left);
    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║     Inventory     ║      Drop        ║
        \\║                   ╚══════════════════║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\        149$                 �� Close   
    , .whole_display);
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
    const arrows = try inventory.add(g.entities.presets.Ammo.get(.arrows));
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║- Arrows 30                           ║
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
        \\║- Arrows 30                     ammo  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Wear an armor" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const jacket = try inventory.add(g.entities.presets.Armor.get(.jacket));
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║] Jacket                              ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    var options = try inventory.chooseItemById(jacket);
    try options.choose("Wear");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║] Jacket                       armor  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Trying to unequip a broken armor" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);

    var inventory = try test_session.openInventory();
    const jacket_id = try inventory.add(g.entities.presets.Armor.get(.jacket));
    try std.testing.expect(try g.meta.breakItem(&test_session.session.registry, prng.random(), jacket_id, null));

    var options = try inventory.chooseItemById(jacket_id);
    try options.choose("Wear");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║[ Jacket                       armor  ║
        \\║¡ Torch                        light  ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    options = try inventory.chooseItemById(jacket_id);
    try options.choose("Unequip");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\┌────────────────Oops!─────────────────┐
        \\│ Looks like it is broken and stuck.   │
        \\│ You will need to repair  it first.   │
        \\└──────────────────────────────────────┘
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    try test_session.pressButton(.a);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                     weapon  ║
        \\║[ Jacket                       armor  ║
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

    test_session.player.health().current_hp = 5;
    var inventory = try test_session.openInventory();
    const potion = try inventory.add(g.entities.presets.Potions.get(.healing_potion));
    const options = try inventory.chooseItemById(potion);
    try options.choose("Drink");
    try std.testing.expect(inventory.isClosed());

    try std.testing.expect(!test_session.session.registry.contains(potion));
    try std.testing.expect(!test_session.player.inventory().items.contains(potion));
    try std.testing.expect(test_session.player.health().current_hp > 5);
    try std.testing.expect(test_session.session.journal.known_potions.contains(.healing));
}
