//! This is collection of information about entities
//! of a game session. It helps to get actual description
//! of weapons, potions and so on.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const Self = @This();

registry: *g.Registry,
known_potions: g.utils.Set(c.Effect.Type),

pub fn init(alloc: std.mem.Allocator, registry: *g.Registry) !Self {
    return .{
        .registry = registry,
        .known_potions = try g.utils.Set(c.Effect.Type).init(alloc),
    };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.known_potions.deinit(alloc);
}

pub fn isKnown(self: Self, entity: g.Entity) bool {
    _ = self;
    _ = entity;
    return false;
}
