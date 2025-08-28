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

pub fn inventory(self: Self) *c.Inventory {
    return self.test_session.session.registry.getUnsafe(self.player, c.Inventory);
}
