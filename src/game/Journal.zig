//! The Journal controls knowledges about entities.
//! Different types of entities have different rules for recognition.
//! As example, an equipment can be recognized eventually, when potions should be drunk.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.journal);

const Self = @This();

const potions_count = @typeInfo(g.descriptions.Potions.Enum).@"enum".fields.len;

alloc: std.mem.Allocator,

registry: *const g.Registry,

potion_colors: [potions_count]g.Color,

/// The key is an id of the entity that is unknown.
/// The value is a count of turns that should be spent to recognize the entity.
/// If the entity is absent in this map, it means that the entity is fully known.
unknown_equipment: std.AutoHashMapUnmanaged(g.Entity, u8) = .empty,

/// A set of known effect of potions.
known_potions: std.AutoHashMapUnmanaged(g.meta.PotionType, void) = .empty,

/// A set of known class of enemies.
known_enemies: std.AutoHashMapUnmanaged(g.meta.EnemyType, void) = .empty,

pub fn init(alloc: std.mem.Allocator, registry: *const g.Registry, seed: u64) !Self {
    var prng = std.Random.DefaultPrng.init(seed);
    const colors_count = @typeInfo(g.Color).@"enum".fields.len;
    std.debug.assert(colors_count >= potions_count);

    var colors: [colors_count]g.Color = undefined;
    @memcpy(&colors, std.meta.tags(g.Color));
    prng.random().shuffle(g.Color, &colors);

    var potion_colors: [potions_count]g.Color = undefined;
    @memcpy(&potion_colors, colors[0..potions_count]);

    return .{ .alloc = alloc, .registry = registry, .potion_colors = potion_colors };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.unknown_equipment.deinit(alloc);
    self.known_potions.deinit(alloc);
    self.known_enemies.deinit(alloc);
}

pub fn isKnown(self: Self, entity: g.Entity) bool {
    if (self.unknown_equipment.contains(entity)) {
        return false;
    }
    if (g.meta.isPotion(self.registry, entity)) |potion_type| {
        return self.known_potions.contains(potion_type);
    }
    if (g.meta.isEnemy(self.registry, entity)) |enemy_type| {
        return self.known_enemies.contains(enemy_type);
    }
    return true;
}

/// Returns a color for an unknown potion, or null if the potion is known.
pub fn unknownPotionColor(self: Self, entity: g.Entity) ?g.Color {
    if (g.meta.isPotion(self.registry, entity)) |potion_type| {
        if (!self.known_potions.contains(potion_type))
            return self.potion_colors[@intFromEnum(potion_type)];
    }
    return null;
}

pub fn markEnemyAsKnown(self: *Self, entity: g.Entity) !void {
    if (g.meta.isEnemy(self.registry, entity)) |enemy_type| {
        log.debug("Mark a creature {d}:{t} as known", .{ entity.id, enemy_type });
        try self.known_enemies.put(self.alloc, enemy_type, {});
    } else {
        std.debug.panic("Entity {d} is not an enemy", .{entity.id});
    }
}

pub fn markPotionAsKnown(self: *Self, entity: g.Entity) !void {
    if (g.meta.isPotion(self.registry, entity)) |potion_type| {
        log.debug("Mark a potion {d}:{t} as known", .{ entity.id, potion_type });
        try self.known_potions.put(self.alloc, potion_type, {});
    } else {
        std.debug.panic("Entity {d} is not a potion", .{entity.id});
    }
}

pub fn onTurnCompleted(self: *Self) !void {
    var itr = self.unknown_equipment.valueIterator();
    while (itr.next()) |value| {
        if (value.* > 0) value.* -= 1;
    }
}
