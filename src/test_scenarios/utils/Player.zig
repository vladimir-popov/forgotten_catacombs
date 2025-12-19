const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const TestSession = @import("TestSession.zig");

const Self = @This();

test_session: *TestSession,
id: g.Entity,

/// Returns a pointer to the Health component of the player
pub fn health(self: Self) *c.Health {
    return self.test_session.session.registry.getUnsafe(self.id, c.Health);
}

/// Returns a pointer to the Inventory component of the player
pub fn inventory(self: Self) *c.Inventory {
    return self.test_session.session.registry.getUnsafe(self.id, c.Inventory);
}

/// Returns a pointer to the Position component of the player
pub fn position(self: Self) *c.Position {
    return self.test_session.session.registry.getUnsafe(self.id, c.Position);
}

pub fn equipment(self: Self) *c.Equipment {
    return self.test_session.session.registry.getUnsafe(self.id, c.Equipment);
}

pub fn target(self: Self) ?g.Entity {
    return switch (self.test_session.session.mode) {
        .play => |play| play.target,
        .explore => |explore| explore.entity_in_focus,
        else => null,
    };
}

/// Moves the player emulating pressing a button appropriated to the passed direction `count` times.
/// After every pressing it runs tick until player's turn happened.
pub fn move(self: Self, direction: p.Direction, count: u8) !void {
    std.debug.assert(self.test_session.session.mode == .play);
    const btn: g.Button.GameButton = switch (direction) {
        .up => .up,
        .down => .down,
        .left => .left,
        .right => .right,
    };
    for (0..count) |_| {
        // complete unfinished turns of enemies
        while (!self.test_session.session.mode.play.is_player_turn) {
            try self.test_session.tick();
        }
        try self.test_session.pressButton(btn);
        // again wait enemies
        while (!self.test_session.session.mode.play.is_player_turn) {
            try self.test_session.tick();
        }
    }
    // one extra tick to draw the actual state
    try self.test_session.tick();
}

pub fn moveTo(self: Self, place: p.Point) !void {
    try self.doCheat(.{ .goto = place });
}

fn doCheat(self: Self, cheat: g.Cheat) !void {
    std.debug.assert(self.test_session.session.mode == .play);
    // complete unfinished turns of enemies
    while (!self.test_session.session.mode.play.is_player_turn) {
        try self.test_session.tick();
    }
    self.test_session.runtime.cheat = cheat;
    // again wait enemies
    while (!self.test_session.session.mode.play.is_player_turn) {
        try self.test_session.tick();
    }
    // one extra tick to draw the actual state
    try self.test_session.tick();
}
