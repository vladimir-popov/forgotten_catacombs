//! The Journal controls knowledges about entities.
//! Different types of entities have different rules for recognition.
//! As example, an equipment can be recognized eventually, when potions should be drunk.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.journal);

const Self = @This();

const TURNS_TO_KNOW = 100;

const potions_count = @typeInfo(g.descriptions.Potions.Enum).@"enum".fields.len;

alloc: std.mem.Allocator,

registry: *g.Registry,

potion_colors: [potions_count]g.Color,

/// The key is an id of the entity that is unknown.
/// The value is a count of turns that should be spent to recognize the entity.
/// When the counter become 0, the entity is moved to the `known_equipment` set.
unknown_equipment: std.AutoHashMapUnmanaged(g.Entity, u8) = .empty,

/// A set of already known equipments
known_equipment: std.AutoHashMapUnmanaged(g.Entity, void) = .empty,

/// A set of known effect of potions.
known_potions: std.AutoHashMapUnmanaged(g.meta.PotionType, void) = .empty,

/// A set of known class of enemies.
known_enemies: std.AutoHashMapUnmanaged(g.meta.EnemyType, void) = .empty,

pub fn init(alloc: std.mem.Allocator, registry: *g.Registry, seed: u64) !Self {
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
    self.known_equipment.deinit(alloc);
    self.known_potions.deinit(alloc);
    self.known_enemies.deinit(alloc);
}

pub fn isKnown(self: Self, entity: g.Entity) bool {
    if (self.known_equipment.contains(entity)) {
        return true;
    }
    if (g.meta.getPotionType(self.registry, entity)) |potion_type| {
        return self.known_potions.contains(potion_type);
    }
    if (g.meta.getEnemyType(self.registry, entity)) |enemy_type| {
        return self.known_enemies.contains(enemy_type);
    }
    if (self.registry.has(entity, c.Modification)) {
        return false;
    }
    return true;
}

pub fn addUnknownEquipment(self: *Self, entity: g.Entity) !void {
    if (!self.known_equipment.contains(entity))
        try self.unknown_equipment.put(self.alloc, entity, TURNS_TO_KNOW);
}

/// Returns a color for an unknown potion, or null if the potion is known.
pub fn unknownPotionColor(self: Self, potion_type: g.meta.PotionType) ?g.Color {
    if (!self.known_potions.contains(potion_type))
        return self.potion_colors[@intFromEnum(potion_type)];
    return null;
}

pub fn markEnemyAsKnown(self: *Self, enemy_type: g.meta.EnemyType) !void {
    log.debug("Mark the creature {t} as known", .{enemy_type});
    try self.known_enemies.put(self.alloc, enemy_type, {});
}

pub fn markPotionAsKnown(self: *Self, potion_type: g.meta.PotionType) !void {
    log.debug("Mark the potion {t} as known", .{potion_type});
    try self.known_potions.put(self.alloc, potion_type, {});
}

pub fn markArmorAsKnown(self: *Self, armor: g.Entity) !void {
    log.debug("Mark the armor {d} as known", .{armor.id});
    try self.known_equipment.put(self.alloc, armor, {});
    try self.registry.set(armor, c.Sprite{ .codepoint = g.codepoints.armor });
}

pub fn markWeaponAsKnown(self: *Self, weapon: g.Entity) !void {
    log.debug("Mark the weapon {d} as known", .{weapon.id});
    try self.known_equipment.put(self.alloc, weapon, {});
    const sprite = self.registry.getUnsafe(weapon, c.Sprite);
    sprite.codepoint = if (self.registry.getUnsafe(weapon, c.Weapon).ammunition_type == null)
        g.codepoints.weapon_melee
    else
        g.codepoints.weapon_ranged;
}

pub fn forgetWeapon(self: *Self, weapon: g.Entity) !void {
    log.debug("Mark the weapon {d} as unknown", .{weapon.id});
    _ = self.known_equipment.remove(weapon);
    const sprite = self.registry.getUnsafe(weapon, c.Sprite);
    sprite.codepoint = if (self.registry.getUnsafe(weapon, c.Weapon).ammunition_type == null)
        g.codepoints.weapon_melee_unknown
    else
        g.codepoints.weapon_ranged_unknown;
}

pub fn onTurnCompleted(self: *Self) !void {
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
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();

    var journal = try init(std.testing.allocator, &registry, 0);
    defer journal.deinit(std.testing.allocator);

    const equipment = g.Entity{ .id = 42 };
    try journal.addUnknownEquipment(equipment);

    // when:
    for (0..TURNS_TO_KNOW + 1) |_| {
        try journal.onTurnCompleted();
    }

    // then:
    try std.testing.expect(!journal.unknown_equipment.contains(equipment));
    try std.testing.expect(journal.known_equipment.contains(equipment));
}
