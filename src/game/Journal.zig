//! The Journal controls knowledges about entities.
//! Different types of entities have different rules for recognition.
//! As example, an equipment can be recognized eventually, when potions should be drunk.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.journal);

const Self = @This();

const TURNS_TO_KNOW = 100;

registry: *g.Registry,
colors: []const g.Color,
/// The key is an id of the entity that is unknown.
/// The value is a count of turns that should be spent to recognize the entity.
/// When the counter become 0, the entity is moved to the `known_equipment` set.
unknown_equipment: std.AutoHashMapUnmanaged(g.Entity, u8) = .empty,
/// A set of already known entities
known_entities: std.AutoHashMapUnmanaged(g.Entity, void) = .empty,
/// A set of known potions (usually means drunk potions).
known_potions: std.AutoHashMapUnmanaged(c.Potion, void) = .empty,
/// A set of known class of enemies.
known_enemies: std.AutoHashMapUnmanaged(g.meta.EnemyType, void) = .empty,

pub fn init(registry: *g.Registry, colors: []const g.Color) !Self {
    return .{ .registry = registry, .colors = colors };
}

/// Try to guess a type of the entity to check its known status correctly.
pub fn isKnown(self: *const Self, entity: g.Entity) bool {
    if (self.known_entities.contains(entity)) {
        return true;
    }
    if (self.registry.get(entity, c.Potion)) |potion| {
        return self.known_potions.contains(potion.*);
    }
    if (g.meta.getEnemyType(self.registry, entity)) |enemy_type| {
        return self.known_enemies.contains(enemy_type);
    }
    if (g.meta.hasModifications(self.registry, entity)) {
        return false;
    }
    return true;
}

pub fn addUnknownEquipment(self: *Self, entity: g.Entity) !void {
    if (!self.known_entities.contains(entity))
        try self.unknown_equipment.put(self.registry.allocator(), entity, TURNS_TO_KNOW);
}

/// Returns a color for an unknown potion, or null if the potion is known.
pub fn unknownPotionColor(self: *const Self, potion: c.Potion) ?g.Color {
    if (!self.known_potions.contains(potion))
        return self.colors[@intFromEnum(potion)];
    return null;
}

pub fn markEnemyAsKnown(self: *Self, enemy_type: g.meta.EnemyType) !void {
    log.debug("Mark the creature {t} as known", .{enemy_type});
    try self.known_enemies.put(self.registry.allocator(), enemy_type, {});
}

pub fn markPotionAsKnown(self: *Self, potion: c.Potion) !void {
    log.debug("Mark the potion {t} as known", .{potion});
    try self.known_potions.put(self.registry.allocator(), potion, {});
}

pub fn markArmorAsKnown(self: *Self, armor: g.Entity) !void {
    log.debug("Mark the armor {d} as known", .{armor.id});
    try self.known_entities.put(self.registry.allocator(), armor, {});
    try self.registry.set(armor, c.Sprite{ .codepoint = g.codepoints.armor });
}

pub fn markTrapAsKnown(self: *Self, trap: g.Entity) !void {
    log.debug("Mark the trap {d} as known", .{trap.id});
    try self.known_entities.put(self.registry.allocator(), trap, {});
}

pub fn markWeaponAsKnown(self: *Self, weapon: g.Entity) !void {
    log.debug("Mark the weapon {d} as known", .{weapon.id});
    try self.known_entities.put(self.registry.allocator(), weapon, {});
    const sprite = self.registry.getUnsafe(weapon, c.Sprite);
    sprite.codepoint = if (self.registry.getUnsafe(weapon, c.Weapon).ammunition_type == null)
        g.codepoints.weapon_melee
    else
        g.codepoints.weapon_ranged;
}

pub fn forgetWeapon(self: *Self, entity: g.Entity) !void {
    log.debug("Mark the weapon {d} as unknown", .{entity.id});
    _ = self.known_entities.remove(entity);
    if (self.registry.get(entity, c.Weapon)) |weapon|
        g.meta.setCodepointOfUnknownWeapon(self.registry, entity, weapon);
}

pub fn forgetArmor(self: *Self, armor: g.Entity) !void {
    log.debug("Mark the armor {d} as unknown", .{armor.id});
    _ = self.known_entities.remove(armor);
    g.meta.setCodepointOfUnknownArmor(self.registry, armor);
}

/// Increase a number of cycles when an unknown item is used
pub fn increaseUsageCounters(self: *Self) !void {
    var not_all_unknown_counters_updated: bool = true;
    while (not_all_unknown_counters_updated) {
        var itr = self.unknown_equipment.iterator();
        not_all_unknown_counters_updated = false;
        update: while (itr.next()) |kv| {
            if (kv.value_ptr.* > 0) {
                kv.value_ptr.* -= 1;
            } else {
                const entity = kv.key_ptr.*;
                _ = self.unknown_equipment.removeByPtr(kv.key_ptr);
                try self.markWeaponAsKnown(entity);
                // the iterator is invalid now, we need to recreate it
                not_all_unknown_counters_updated = true;
                break :update;
            }
        }
    }
}

test "Move unknown equipment to known after N turns" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    var journal = try init(&registry, std.enums.values(g.Color));
    const equipment = try registry.addNewEntity(g.entities.presets.Weapons.get(.pickaxe));
    try journal.addUnknownEquipment(equipment);

    // when:
    for (0..TURNS_TO_KNOW + 1) |_| {
        try journal.increaseUsageCounters();
    }

    // then:
    try std.testing.expect(!journal.unknown_equipment.contains(equipment));
    try std.testing.expect(journal.known_entities.contains(equipment));
}
