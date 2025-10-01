//! The Journal controls knowledges about entities.
//! Different types of entities have different rules for recognition.
//! An equipment can be recognized eventually, when potions should be drunk.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const Self = @This();

pub const KNOWN_ENTITY = 0;
pub const WEAPON_RECOGNITION_SPEED = 50;

alloc: std.mem.Allocator,
registry: *g.Registry,
/// The key is an id of the entity that is known if the value is zero.
/// The value is a count of turns that should be spent to recognize the entity.
known_equipment: std.AutoHashMapUnmanaged(g.Entity, u8) = .empty,
known_potions: std.AutoHashMapUnmanaged(c.Effect.Type, void) = .empty,

pub fn init(alloc: std.mem.Allocator, registry: *g.Registry) !Self {
    return .{ .alloc = alloc, .registry = registry };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.known_equipment.deinit(alloc);
}

pub fn isKnown(self: Self, entity: g.Entity) bool {
    if (g.meta.isPotion(self.registry, entity)) {
        if (self.registry.get(entity, c.Effect)) |effect|
            return self.known_potions.contains(effect.effect_type);
    }
    if (self.known_equipment.get(entity)) |value| {
        return value == KNOWN_ENTITY;
    }
    return false;
}

pub fn markAsKnown(self: *Self, entity: g.Entity) !void {
    if (g.meta.isPotion(self.registry, entity)) {
        if (self.registry.get(entity, c.Effect)) |effect| {
            try self.known_potions.put(self.alloc, effect.effect_type, {});
        }
    } else {
        try self.known_equipment.put(self.alloc, entity, KNOWN_ENTITY);
    }
}

pub fn onTurnCompleted(self: *Self) !void {
    var itr = self.known_equipment.valueIterator();
    while (itr.next()) |value| {
        if (value.* > 0) value.* -= 1;
    }
}
