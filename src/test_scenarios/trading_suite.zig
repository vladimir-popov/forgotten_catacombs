const std = @import("std");
const g = @import("game");
const c = g.components;
const Options = @import("utils/Options.zig");
const Shop = @import("utils/Shop.zig");
const TestSession = @import("utils/TestSession.zig");

test "Init near the shop" {
    var test_session: TestSession = undefined;
    _ = try initNearShopWithMoney(&test_session, 40);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    try test_session.runtime.display.expectLooksLike(
        \\╔═══════════════════╗══════════════════╗
        \\║        Buy        ║      Sell        ║
        \\║                   ╚══════════════════║
        \\║] Jacket                         52$ ▒║
        \\║¡ Oil lamp                       75$ ░║
        \\║¿ A white potion                 45$ ░║
        \\║} Light crossbow                 75$ ░║
        \\║% Apple                          15$ ░║
        \\║¿ A blue potion                  45$ ░║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Your money:   40$    Close     Choose ⇧
    , .whole_display);
}

test "Buy something" {
    // given:
    var test_session: TestSession = undefined;
    const shop = try initNearShopWithMoney(&test_session, 1000);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const items_before = test_session.player.inventory().items.size();

    // when:
    const options = try shop.chooseItemByIndex(0);
    try options.choose("Buy");
    const items_after = test_session.player.inventory().items.size();

    // then:
    try std.testing.expect(test_session.player.wallet().money < 1000);
    try std.testing.expect(items_after > items_before);
}

test "Trying to buy when NOT enough money" {
    // given:
    var test_session: TestSession = undefined;
    const shop = try initNearShopWithMoney(&test_session, 0);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const items_before = test_session.player.inventory().items.size();

    // when:
    const options = try shop.chooseItemByIndex(0);
    try options.choose("Buy");

    // then:
    try std.testing.expectEqual(items_before, test_session.player.inventory().items.size());
    try test_session.runtime.display.expectLooksLike(
        \\║┌────────────────────────────────────┐║
        \\║│          You have not enough       │║
        \\║│                 money.             │║
        \\║└────────────────────────────────────┘║
    , .{ .region = .init(4, 1, 4, 40) });
}

test "Selling something" {
    // given:
    var test_session: TestSession = undefined;
    const shop = try initNearShopWithMoney(&test_session, 0);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const items_before = test_session.player.inventory().items.size();

    // when:
    try test_session.pressButton(.right);
    const options = try shop.chooseItemByIndex(0);
    try options.choose("Sell");
    const items_after = test_session.player.inventory().items.size();

    // then:
    try std.testing.expect(test_session.player.wallet().money > 0);
    try std.testing.expect(items_after < items_before);
}

test "Trying to sell when the trader doesn't have enough money" {
    // given:
    var test_session: TestSession = undefined;
    const shop = try initNearShopWithMoney(&test_session, 0);
    defer test_session.deinit();
    errdefer test_session.printDisplay();

    const items_before = test_session.player.inventory().items.size();

    // when:
    shop.currentShop().balance = 0;
    try test_session.pressButton(.right);
    const options = try shop.chooseItemByIndex(0);
    try options.choose("Sell");

    // then:
    try std.testing.expectEqual(items_before, test_session.player.inventory().items.size());
    try test_session.runtime.display.expectLooksLike(
        \\╔══════════════════╔═══════════════════╗
        \\║        Buy       ║       Sell        ║
        \\║══════════════════╝                   ║
        \\║┌────────────────────────────────────┐║
        \\║│          Traider doesn't have      │║
        \\║│              enough money          │║
        \\║└────────────────────────────────────┘║
        \\║                                      ║
        \\║                                      ║
        \\╚══════════════════════════════════════╝
        \\════════════════════════════════════════
        \\ Traider's:     0$           �� Close   
    , .whole_display);
}

fn initNearShopWithMoney(test_session: *TestSession, money: u16) !Shop {
    std.testing.random_seed = 100500;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    test_session.player.position().place = g.dungeon.FirstLocation.trader_place.movedTo(.right);
    test_session.player.wallet().money = money;
    try test_session.pressButton(.left);
    return .{ .test_session = test_session };
}
