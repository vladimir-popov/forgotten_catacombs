const std = @import("std");
const g = @import("game");
const TestSession = @import("utils/TestSession.zig");

test "Describe an item" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const options = try inventory.chooseItemByName("Torch");
    try options.choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║┌───────────────Torch────────────────┐║
        \\║│ Wooden handle, cloth wrap, burning▒│║
        \\║│ flame. Lasts until the fire dies. ░│║
        \\║│                                   ░│║
        \\║│ Damage:                           ░│║
        \\║│   physical 2-3                    ░│║
        \\║│   burning 1-1                     ░│║
        \\║└────────────────────────────────────┘║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Describe an unknown potion" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();

    const inventory = try test_session.openInventory();
    const potion = try inventory.add(g.presets.Items.values.get(.healing_potion).*);
    const options = try inventory.chooseItemById(potion);
    try options.choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║              Inventory               ║
        \\║┌───────────A green potion───────────┐║
        \\║│ A swirling liquid of green color   │║
        \\║│ rests in a vial.                   │║
        \\║│                                    │║
        \\║│ Weight: 10                         │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Describe a known potion (after drinking a similar)" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();

    // Drink a potion:
    var inventory = try test_session.openInventory();
    const potion_to_drink = try inventory.add(g.presets.Items.values.get(.healing_potion).*);
    var options = try inventory.chooseItemById(potion_to_drink);
    try options.choose("Drink");

    // Check the description:
    inventory = try test_session.openInventory();
    const potion_to_describe = try inventory.add(g.presets.Items.values.get(.healing_potion).*);
    options = try inventory.chooseItemById(potion_to_describe);
    try options.choose("Describe");

    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════════════════════════╗
        \\║┌──────────A healing potion──────────┐║
        \\║│ A brew that glows faintly, as if  ▒│║
        \\║│ mends alive. It warms your veins  ░│║
        \\║│ and your wounds instantly.        ░│║
        \\║│                                   ░│║
        \\║│ Effects:                          ░│║
        \\║│   healing 20-25                   ░│║
        \\║└────────────────────────────────────┘║
        \\╚══════════════════════════════════════╝
    , .game_area);
}

test "Describe an unknown enemy" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    const rat = try test_session.session.level.addEnemy(.sleeping, g.entities.rat(pp));
    try test_session.tick();

    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try std.testing.expectEqual(rat, test_session.player.target());
    try test_session.pressButton(.a);

    try test_session.runtime.display.expectLooksLike(
        \\######################################30
        \\┌─────────────────Rat──────────────────┐
        \\│ A big, nasty rat with vicious eyes   │
        \\│ that thrives in dark corners and     │
        \\│ forgotten cellars.                   │
        \\│                                      │
        \\│ Who knows what to expect from this   │
        \\│ creature?                            │
        \\└──────────────────────────────────────┘
        \\~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    , .game_area);
}

test "Describe a known enemy (after killing a similar creature)" {
    var test_session: TestSession = undefined;
    try test_session.initEmpty(std.testing.allocator);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    // Prepare a game session:
    const pp = test_session.player.position().place.movedTo(.up);
    var rat_to_kick_components = g.entities.rat(pp);
    rat_to_kick_components.health.?.current = 1;
    const rat_to_kick_id = try test_session.session.level.addEnemy(.sleeping, rat_to_kick_components);
    const rat_to_describe = try test_session.session.level.addEnemy(.sleeping, g.entities.rat(pp.movedToNTimes(.up, 5)));
    try test_session.tick();

    // kill the rat
    var attempt: usize = 0;
    while (test_session.session.registry.get(rat_to_kick_id, g.components.Health)) |health| {
        if (health.current == 0) break;

        try test_session.pressButton(.up);

        if (attempt > 15) return error.ToManyAttemptsToKick;
        attempt += 1;
    }

    // Check description of the second rat
    try test_session.exploreMode();
    try test_session.pressButton(.up);
    try std.testing.expectEqual(rat_to_describe, test_session.player.target());
    try test_session.pressButton(.a);

    try test_session.runtime.display.expectLooksLike(
        \\┌─────────────────Rat──────────────────┐
        \\│ A big, nasty rat with vicious eyes  ▒│
        \\│ that thrives in dark corners and    ░│
        \\│ forgotten cellars.                  ░│
        \\│                                     ░│
        \\│ Health: 10/10                       ░│
        \\│ Damage:                             ░│
        \\│   physical 1-3                      ░│
        \\│                                     ░│
        \\└──────────────────────────────────────┘
    , .game_area);
}
