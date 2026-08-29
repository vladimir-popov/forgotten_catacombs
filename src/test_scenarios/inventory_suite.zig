const std = @import("std");
const g = @import("game");
const c = g.components;
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
        \\║/ Pickaxe                      weapon ║
        \\║¡ Torch                         light ║
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
    const modal_window = try inventory.chooseItemByName("Torch");
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

    try (try modal_window.asOptions()).choose("Unequip");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
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
    const modal_window = try inventory.chooseItemByName("Pickaxe");
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

    try (try modal_window.asOptions()).choose("Unequip");
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
        \\║\ Pickaxe                      weapon ║
        \\║¡ Torch                         light ║
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
    const modal_window = try inventory.chooseItemByName("Torch");
    try (try modal_window.asOptions()).choose("Drop");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╗═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║                  ╚═══════════════════║
        \\║/ Pickaxe                      weapon ║
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
        const modal_window = try inventory.chooseItemByIndex(0);
        try (try modal_window.asOptions()).choose("Drop");
    }
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╗═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║                  ╚═══════════════════║
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
    var modal_window = try inventory.chooseItemByName("Pickaxe");
    try (try modal_window.asOptions()).choose("Drop");
    try test_session.pressButton(.right);
    // Pickup:
    modal_window = try inventory.chooseItemByName("Pickaxe");
    try (try modal_window.asOptions()).choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                         light ║
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
        const modal_window = try inventory.chooseItemByIndex(0);
        try (try modal_window.asOptions()).choose("Drop");
    }
    try test_session.pressButton(.right);
    // Pickup:
    const modal_window = try inventory.chooseItemByIndex(0);
    try (try modal_window.asOptions()).choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
    , .{ .region = .init(1, 1, 3, 40) });
}

test "Pickuping all items from a pile should lead to removing the 'Drop' tab" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    // Drop everything from the inventory:
    var inventory = try test_session.openInventory();
    while (!inventory.isInvetoryEmpty()) {
        const modal_window = try inventory.chooseItemByIndex(0);
        try (try modal_window.asOptions()).choose("Drop");
    }
    try test_session.pressButton(.right);
    // Pickup everything back:
    while (!inventory.isDropEmpty()) {
        const modal_window = try inventory.chooseItemByIndex(0);
        try (try modal_window.asOptions()).choose("Take");
    }
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
    , .{ .region = .init(1, 1, 3, 40) });
}

test "Pickuping extra items should be imposible" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Drop something from the inventory:
    var inventory = try test_session.openInventory();
    var modal_window = try inventory.chooseItemByIndex(0);
    try (try modal_window.asOptions()).choose("Drop");

    // Fill the inventory
    const inventory_component = test_session.session.registry.getUnsafe(test_session.player.id, c.Inventory);
    while (!inventory_component.isFull()) {
        const item_id = try test_session.session.registry.addNewEntity(g.entities.presets.Items.get(.torch));
        try inventory_component.items.add(item_id);
    }
    const inventory_size_before = inventory_component.items.size();

    // Switch to the 'Drop' tab
    try test_session.pressButton(.right);

    // Try to pickup something
    try std.testing.expect(!inventory.isDropEmpty());
    modal_window = try inventory.chooseItemByIndex(0);
    try (try modal_window.asOptions()).choose("Take");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║══════════════════╝                   ║
        \\║┌────────────────────────────────────┐║
        \\║│        Your inventory is full!     │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
    try std.testing.expect(!inventory.isDropEmpty());
    try std.testing.expectEqual(inventory_size_before, inventory_component.items.size());
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
        \\╔══════════════════╗═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║                  ╚═══════════════════║
        \\║/ Pickaxe                      weapon ║
        \\║¡ Torch                         light ║
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
    const modal_window = try inventory.chooseItemByIndex(0);
    try (try modal_window.asOptions()).choose("Take");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
        \\║¡ Torch                         light ║
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
        const modal_window = try inventory.chooseItemByIndex(0);
        try (try modal_window.asOptions()).choose("Drop");
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
    const modal_window = try inventory.chooseItemByName("Gold");
    try (try modal_window.asOptions()).choose("Take");
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
        \\╔══════════════════╗═══════════════════╗
        \\║     Inventory    ║       Drop        ║
        \\║                  ╚═══════════════════║
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
    var modal_window = try inventory.chooseItemByName("Torch");
    try (try modal_window.asOptions()).choose("Unequip");
    modal_window = try inventory.chooseItemByName("Torch");
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
    try (try modal_window.asOptions()).choose("Use as a weapon");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                             ║
        \\║¡ Torch                        weapon ║
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
        \\║/ Pickaxe                      weapon ║
        \\║- Arrows 30                           ║
        \\║¡ Torch                         light ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    var modal_window = try inventory.chooseItemById(arrows);
    try (try modal_window.asOptions()).choose("Put to quiver");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
        \\║- Arrows 30                      ammo ║
        \\║¡ Torch                         light ║
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
        \\║/ Pickaxe                      weapon ║
        \\║] Jacket                              ║
        \\║¡ Torch                         light ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    var modal_window = try inventory.chooseItemById(jacket);
    try (try modal_window.asOptions()).choose("Wear");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
        \\║] Jacket                        armor ║
        \\║¡ Torch                         light ║
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

    var modal_window = try inventory.chooseItemById(jacket_id);
    try (try modal_window.asOptions()).choose("Wear");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
        \\║[ Jacket                        armor ║
        \\║¡ Torch                         light ║
        \\║                                      ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    modal_window = try inventory.chooseItemById(jacket_id);
    try (try modal_window.asOptions()).choose("Unequip");
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
        \\║/ Pickaxe                      weapon ║
        \\║[ Jacket                        armor ║
        \\║¡ Torch                         light ║
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
    const potion = g.entities.presets.Potions.get(.healing_potion);
    const potion_id = try inventory.add(potion);
    const modal_window = try inventory.chooseItemById(potion_id);
    try (try modal_window.asOptions()).choose("Drink");
    try std.testing.expect(inventory.isClosed());

    try std.testing.expect(!test_session.session.registry.contains(potion_id));
    try std.testing.expect(!test_session.player.inventory().items.contains(potion_id));
    try std.testing.expect(test_session.player.health().current_hp > 5);
    try std.testing.expect(test_session.session.journal.known_potions.contains(potion.potion.?));
}

test "An unrecognized oil can't be used" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Prepare inventory:
    var inventory = try test_session.openInventory();
    // Add unrecognized oil
    const oil = g.entities.presets.Potions.get(.oil_potion);
    const oil_id = try inventory.add(oil);
    // Check available options in menu:
    _ = try inventory.chooseItemById(oil_id);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║┌────────────────────────────────────┐║
        \\║│               Drink                │║
        \\║│                Drop                │║
        \\║│              Describe              │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Combining oil with lamp should increase lamp's charge" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Prepare inventory:
    var inventory = try test_session.openInventory();
    // Add recognized oil
    const oil = g.entities.presets.Potions.get(.oil_potion);
    const oil_id = try inventory.add(oil);
    try test_session.session.journal.markPotionAsKnown(oil.potion.?);
    // Add used lamp
    var lamp = g.entities.presets.Items.get(.oil_lamp);
    lamp.source_of_light.?.charge = 0;
    const lamp_id = try inventory.add(lamp);

    // Scenario:
    const modal_window = try inventory.chooseItemById(oil_id);
    try (try modal_window.asOptions()).choose("Combine");
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║┌────────────────────────────────────┐║
        \\║│¡ Oil lamp                          │║
        \\║│                                    │║
        \\║│                                    │║
        \\║│                                    │║
        \\║│                                    │║
        \\║│                                    │║
        \\║└────────────────────────────────────┘║
        \\╚══════════════════════════════════════╝
    , .game_area);
    // Combine oil with lamp
    try (try modal_window.asOptions()).chooseByIndex(0);
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║                                      ║
        \\║/ Pickaxe                      weapon ║
        \\║¿ Oil                                 ║
        \\║¡ Torch                         light ║
        \\║¡ Oil lamp                            ║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);

    // Then:
    const charge = test_session.session.registry.getUnsafe(lamp_id, c.SourceOfLight).charge;
    try std.testing.expect(charge > 0);
}
