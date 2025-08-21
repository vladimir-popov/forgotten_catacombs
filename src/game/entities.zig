//! This is a collection of util methods to work with entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const Self = @This();

///
registry: g.Registry,

pub fn isEnemy(self: *const Self, entity: g.Entity) bool {
    return self.registry.has(entity, c.EnemyState);
}

pub fn isItem(self: *const Self, entity: g.Entity) bool {
    return self.registry.has(entity, c.Weight);
}

pub fn isEquipment(self: *const Self, item: g.Entity) bool {
    return self.isItem(item) and
        (self.registry.has(item, c.Damage) or self.registry.has(item, c.SourceOfLight));
}

pub fn getSourceOfLight(self: *const Self, player: g.Entity) ?*c.SourceOfLight {
    if (self.registry.get(player, c.Equipment)) |equipment| {
        if (equipment.light) |light| {
            return self.registry.get(light, c.SourceOfLight);
        }
    }
    return null;
}
