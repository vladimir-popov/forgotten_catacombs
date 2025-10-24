//! The Journal controls knowledges about entities.
//! Different types of entities have different rules for recognition.
//! As example, an equipment can be recognized eventually, when potions should be drunk.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.journal);

const Self = @This();

alloc: std.mem.Allocator,

registry: *const g.Registry,

potion_colors: [c.Effect.TypesCount]g.Color,

/// The key is an id of the entity that is unknown.
/// The value is a count of turns that should be spent to recognize the entity.
/// If the entity is absent in this map, it means that the entity is fully known.
unknown_equipment: std.AutoHashMapUnmanaged(g.Entity, u8) = .empty,

/// A set of known effect of potions.
known_potions: std.AutoHashMapUnmanaged(c.Effect.Type, void) = .empty,

/// A set of known class of enemies.
known_enemies: std.AutoHashMapUnmanaged(g.presets.Descriptions.Tag, void) = .empty,

pub fn init(alloc: std.mem.Allocator, registry: *const g.Registry, rand: std.Random) !Self {
    const colors_count = @typeInfo(g.Color).@"enum".fields.len;
    std.debug.assert(colors_count >= c.Effect.TypesCount);

    var colors: [colors_count]g.Color = undefined;
    @memcpy(&colors, std.meta.tags(g.Color));
    rand.shuffle(g.Color, &colors);

    var potion_colors: [c.Effect.TypesCount]g.Color = undefined;
    @memcpy(&potion_colors, colors[0..c.Effect.TypesCount]);

    return .{ .alloc = alloc, .registry = registry, .potion_colors = potion_colors };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.unknown_equipment.deinit(alloc);
    self.known_potions.deinit(alloc);
    self.known_enemies.deinit(alloc);
}

pub fn isKnown(self: Self, entity: g.Entity) bool {
    if (g.meta.isPotion(self.registry, entity)) {
        if (self.registry.get(entity, c.Effect)) |effect|
            return self.known_potions.contains(effect.effect_type);
    }
    if (g.meta.isEnemy(self.registry, entity)) {
        if (self.registry.get(entity, c.Description)) |description|
            return self.known_enemies.contains(description.preset);
    }
    if (!self.unknown_equipment.contains(entity)) {
        return true;
    }
    return false;
}

pub fn isUnknownPotion(self: Self, entity: g.Entity) ?g.Color {
    if (g.meta.isPotion(self.registry, entity)) {
        if (self.registry.get(entity, c.Effect)) |effect|
            if (!self.known_potions.contains(effect.effect_type))
                return self.potion_colors[@intFromEnum(effect.effect_type)];
    }
    return null;
}

pub fn markPotionAsKnown(self: *Self, entity: g.Entity) !void {
    if (self.registry.get(entity, c.Effect)) |effect| {
        log.debug("Mark a potion {d}:{t} as known", .{ entity.id, effect.effect_type });
        try self.known_potions.put(self.alloc, effect.effect_type, {});
    }
}

pub fn markEnemyAsKnown(self: *Self, entity: g.Entity) !void {
    if (self.registry.get(entity, c.Description)) |description| {
        log.debug("Mark a creature {d}:{t} as known", .{ entity.id, description.preset });
        try self.known_enemies.put(self.alloc, description.preset, {});
    }
}

pub fn onTurnCompleted(self: *Self) !void {
    var itr = self.unknown_equipment.valueIterator();
    while (itr.next()) |value| {
        if (value.* > 0) value.* -= 1;
    }
}
