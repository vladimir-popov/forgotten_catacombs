const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Describe an item" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const modal_window = try inventory.chooseItemByName("Torch");
    try (try modal_window.asOptions()).choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\┌────────────────Torch─────────────────┐
        \\│ Wooden handle, cloth wrap, burning  ▒│
        \\│ flame. Lasts until the  fire dies.  ░│
        \\│ It can be  used as a weapon out of  ░│
        \\│ despair.                            ░│
        \\│                                     ░│
        \\│ This is a primitive weapon.         ░│
        \\│ Damage: 1-1                         ░│
        \\│                                     ░│
        \\└──────────────────────────────────────┘
    , .game_area);
}

test "Describe an unknown potion" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const potion = try inventory.add(g.entities.presets.Potions.get(.healing));
    const modal_window = try inventory.chooseItemById(potion);
    try (try modal_window.asOptions()).choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\┌────────────A green potion────────────┐
        \\│ A swirling liquid of green color     │
        \\│ rests in a vial.                     │
        \\│                                      │
        \\│                                      │
        \\│                                      │
        \\│                                      │
        \\│                                      │
        \\│                                      │
        \\└──────────────────────────────────────┘
    , .game_area);
}

test "Describe a known potion (after drinking a similar)" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Drink a potion:
    var inventory = try test_session.openInventory();
    const potion_to_drink = try inventory.add(g.entities.presets.Potions.get(.healing));
    var modal_window = try inventory.chooseItemById(potion_to_drink);
    try (try modal_window.asOptions()).choose("Drink");

    // Check the description:
    inventory = try test_session.openInventory();
    const potion_to_describe = try inventory.add(g.entities.presets.Potions.get(.healing));
    modal_window = try inventory.chooseItemById(potion_to_describe);
    try (try modal_window.asOptions()).choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\┌───────────────Healing────────────────┐
        \\│ The  warm  medicinal brew smells of  │
        \\│ herbs  and  honey.  A  few  careful  │
        \\│ swallows restore strength, dull the  │
        \\│ pain,  and help the body endure its  │
        \\│ deepest wounds.                      │
        \\│                                      │
        \\│                                      │
        \\│                                      │
        \\└──────────────────────────────────────┘
    , .game_area);
}

test "Describe an unknown enemy" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    const rat = try test_session.session.level.addEnemy(.sleeping, g.entities.enemyAtPlace(.rat, pp));
    try test_session.tick(.{});

    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try std.testing.expectEqual(rat, test_session.player.target());
    try test_session.pressButton(.b);

    try test_session.runtime.display.expectLooksLike(
        \\┌─────────────────Rat──────────────────┐
        \\│ A big, nasty rat with vicious eyes   │
        \\│ that thrives in dark corners and     │
        \\│ forgotten cellars.                   │
        \\│                                      │
        \\│ Who knows what to expect from this   │
        \\│ creature?                            │
        \\│                                      │
        \\│                                      │
        \\└──────────────────────────────────────┘
    , .game_area);
}

test "Describe a known enemy (after killing a similar creature)" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    // Prepare a game session:
    test_session.player.position().place.move(.up);
    const p1 = test_session.player.position().place.movedTo(.up);
    const p2 = test_session.player.position().place.movedTo(.left);

    var rat_to_kick_components = g.entities.enemyAtPlace(.rat, p1);
    rat_to_kick_components.health.?.current_hp = 1;
    const rat_to_kick_id = try test_session.session.level.addEnemy(.sleeping, rat_to_kick_components);

    const rat_to_describe = try test_session.session.level.addEnemy(.sleeping, g.entities.enemyAtPlace(.rat, p2));
    try test_session.tick(.{});
    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\#•••••••••••••#     #••••••••••••••••••#
        \\#•••┌───┐•••••###+###•••••••••••┌───┐••#
        \\#•••│   +•••••••••••••••••••••••+   │••#
        \\#•••└───┘•••••••••••••••••••••••└───┘••#
        \\#•••┌───┐••••••••••••••••••••••••••••••#
        \\#•••│   +•••••••••••r••••••••••••••••••#
        \\#•••└───┘••••••••••r@••••••••••••••••••#
        \\~~~~~~~~~~~~~~~~~~~│<│~~~~~~~~~~~~~~~~~~
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    , .game_area);

    // kill the rat
    var attempt: usize = 0;
    while (test_session.session.registry.get(rat_to_kick_id, g.components.Health)) |health| {
        // wait when notification disappears
        test_session.runtime.current_millis += 3000;
        if (health.current_hp == 0) break;

        try test_session.pressButton(.up);

        if (attempt > 15) return error.ToManyAttemptsToKick;
        attempt += 1;
    }

    // Check description of the second rat
    try test_session.exploreMode();
    try test_session.pressButton(.left);
    try std.testing.expectEqual(rat_to_describe, test_session.player.target());
    try test_session.pressButton(.b);

    try test_session.runtime.display.expectLooksLike(
        \\┌─────────────────Rat──────────────────┐
        \\│ A big, nasty rat with vicious eyes  ▒│
        \\│ that thrives in dark corners and    ░│
        \\│ forgotten cellars.                  ░│
        \\│                                     ░│
        \\│ Health: 10/10                       ░│
        \\│                                     ░│
        \\│ Damage: 3-8                         ░│
        \\│                                     ░│
        \\└──────────────────────────────────────┘
    , .game_area);
}
