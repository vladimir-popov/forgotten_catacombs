const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("utils/TestSession.zig");
const Inventory = @import("utils/Inventory.zig");

test "Drink a healing potion" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const health = test_session.session.registry.getUnsafe(test_session.player.id, c.Health);
    health.current_hp -= 10;
    const health_before = health.current_hp;

    try drinkPotion(&test_session, .healing);

    try std.testing.expect(health.current_hp > health_before);
}

test "Drink a poison" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const health = test_session.session.registry.getUnsafe(test_session.player.id, c.Health);
    const health_before = health.current_hp;

    try drinkPotion(&test_session, .poison);

    try std.testing.expect(health.current_hp < health_before);
}

test "Drink an antidote" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    try drinkPotion(&test_session, .poison);
    try std.testing.expect(test_session.session.registry.has(test_session.player.id, c.Poison));

    try drinkPotion(&test_session, .antidote);
    try std.testing.expect(!test_session.session.registry.has(test_session.player.id, c.Poison));
}

test "Drink an oil" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const health = test_session.session.registry.getUnsafe(test_session.player.id, c.Health);
    const health_before = health.current_hp;

    try drinkPotion(&test_session, .oil);

    try std.testing.expect(health.current_hp < health_before);
}

test "Drink an acid potion" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const health = test_session.session.registry.getUnsafe(test_session.player.id, c.Health);
    const health_before = health.current_hp;

    try drinkPotion(&test_session, .acid);

    try std.testing.expect(health.current_hp < health_before);
}

test "Drink a liquid fire potion" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const health = test_session.session.registry.getUnsafe(test_session.player.id, c.Health);
    const health_before = health.current_hp;

    try drinkPotion(&test_session, .liquid_fire);

    try std.testing.expect(health.current_hp < health_before);
}

test "Drink an bouillon" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const hunger = test_session.session.registry.getUnsafe(test_session.player.id, c.Hunger);
    hunger.turns_after_eating += 100;
    const hunger_before = hunger.turns_after_eating;

    try drinkPotion(&test_session, .bouillon);

    try std.testing.expect(hunger.turns_after_eating < hunger_before);
}

test "Drink an spoiled bouillon" {
    var test_session: TestSession = undefined;
    try test_session.initOnFirstLevel(std.testing.allocator, std.testing.io);
    defer test_session.deinit();

    const hunger = test_session.session.registry.getUnsafe(test_session.player.id, c.Hunger);
    const hunger_before = hunger.turns_after_eating;

    try drinkPotion(&test_session, .spoiled_bouillon);

    try std.testing.expect(hunger.turns_after_eating > hunger_before);
}

fn drinkPotion(test_session: *TestSession, potion: g.entities.presets.Potions.Tag) !void {
    const inventory = try test_session.openInventory();
    const potion_id = try inventory.add(g.entities.presets.Potions.get(potion));
    var modal_window = try inventory.chooseItemById(potion_id);
    try (try modal_window.asOptions()).choose("Drink");
    try inventory.close();

    try std.testing.expect(!test_session.player.inventory().items.contains(potion_id));
    try std.testing.expect(!test_session.session.registry.contains(potion_id));
}
