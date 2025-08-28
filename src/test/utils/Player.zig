const std = @import("std");
const g = @import("game");
const c = g.components;
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,
player: g.Entity,

pub fn health(self: Self) *c.Health {
    return self.test_session.session.registry.getUnsafe(self.player, c.Health);
}

pub fn addToInventory(self: Self, item: c.Components) !g.Entity {
    const item_id = try self.test_session.session.registry.addNewEntity(item);
    try self.test_session.session.registry.getUnsafe(self.player, c.Inventory).items.add(item_id);
    return item_id;
}
