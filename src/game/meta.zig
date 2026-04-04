//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;

const log = std.log.scoped(.meta);

pub const PotionType = g.descriptions.Potions.Enum;
pub const EnemyType = g.descriptions.Enemies.Enum;
pub const PlayerArchetype = g.descriptions.Archetypes.Enum;
pub const Skill = g.descriptions.Skills.Enum;

/// A numbers of required exp point for level up.
/// The 0 element is a required amount of exp point to get the
/// second level.
pub const Levels = [_]u16{ 500, 1000, 15000, std.math.maxInt(u16) };

pub inline fn experienceToNextLevel(current_level: u4) u16 {
    return Levels[current_level - 1];
}

/// Any entity with weight is item.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Returns a type of a potion if it has description preset from appropriate namespace.
pub inline fn getPotionType(registry: *const g.Registry, entity: g.Entity) ?PotionType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(PotionType, @tagName(descr.preset))
    else
        null;
}

/// Returns a type of the enemy if it has a description preset from an appropriate namespace.
pub inline fn getEnemyType(registry: *const g.Registry, entity: g.Entity) ?EnemyType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(EnemyType, @tagName(descr.preset))
    else
        null;
}

/// Returns the id of the item with maximal radius of light through all equipped sources of the light,
/// or null and default value.
pub fn getLight(registry: *const g.Registry, equipment: *const c.Equipment) struct { ?g.Entity, f32 } {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return .{ id, sol.radius };
        }
    }
    if (equipment.weapon) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return .{ id, sol.radius };
        }
    }
    return .{ null, 1.0 };
}

/// Returns an id of the equipped weapon, or the `actor`, because any enemy must be able to provide
/// a damage without equipment. The player and humanoid enemies should be able to damage by hands,
/// animal should bite (but, hands and tooth are not equipped as a weapon).
pub fn getWeapon(registry: *const g.Registry, actor: g.Entity) struct { g.Entity, c.Weapon } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon_id| {
            const weapon = registry.get(weapon_id, c.Weapon) orelse
                std.debug.panic("A Weapon component is not provided for the weapon entity {d}", .{weapon_id.id});
            return .{ weapon_id, weapon.* };
        }
    }
    // "tooth" and "bare hands" are not equipped weapon,
    // just emulate them
    return .{ actor, registry.getUnsafe(actor, c.Weapon).* };
}

/// If the actor has equipped armor, this method returns id of the equipped armor and its
/// protection;
/// If the actor has a protection directly (as many enemies do), this method returns the `actor` and
/// its protection;
/// Otherwise the `actor` and null will be returned.
pub fn getArmor(registry: *const g.Registry, actor: g.Entity) struct { g.Entity, ?c.Protection } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.armor) |armor_id| {
            const protection = registry.getUnsafe(armor_id, c.Protection);
            return .{ armor_id, protection.* };
        }
    }
    if (registry.get(actor, c.Protection)) |protection|
        return .{ actor, protection.* };

    return .{ actor, null };
}

pub fn getAmmunition(registry: *const g.Registry, actor: g.Entity) ?struct { g.Entity, *c.Ammunition } {
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.ammunition) |ammo_id| {
            if (registry.get(ammo_id, c.Ammunition)) |ammo| {
                return .{ ammo_id, ammo };
            }
        }
    }

    // Some animals can spit
    if (registry.get(actor, c.Ammunition)) |ammo| {
        return .{ actor, ammo };
    }

    return null;
}

/// Merges the original weapon's effects with modifications possibly applied to the weapon
pub fn getActualDamage(registry: *const g.Registry, weapon_id: g.Entity, weapon: c.Weapon) c.Effects {
    var effects: c.Effects = weapon.damage;
    // TODO: summarize effects with ammo
    // Merge with modifications
    if (registry.get(weapon_id, c.Modification)) |modifications| {
        modifications.applyTo(&effects);
    }
    // Return a copy of the merged effects
    return effects;
}

/// Merges the original armor's effects with modifications possibly applied to the armor
pub fn getActualProtection(registry: *const g.Registry, armor_id: g.Entity, protection: ?c.Protection) c.Protection {
    if (protection) |pr| {
        var effects: c.Effects = pr.resistance;
        // Merge with modifications
        if (registry.get(armor_id, c.Modification)) |modifications| {
            modifications.applyTo(&effects);
        }
        // Return a copy of the merged effects
        return .{ .resistance = effects };
    } else {
        return .zeros;
    }
}

pub fn statsFromArchetype(archetype: PlayerArchetype) c.Stats {
    return switch (archetype) {
        .adventurer => .init(0, 0, 0, 0, 0),
        .archeologist => .init(-2, 0, 1, 2, 0),
        .vandal => .init(2, 0, -1, -1, 2),
        .rogue => .init(-1, 2, 1, 0, -1),
    };
}

pub inline fn isLevelUp(registry: *g.Registry, player: g.Entity) bool {
    if (registry.get(player, c.LevelUp)) |level_up| {
        return level_up.last_handled_level < registry.getUnsafe(player, c.Experience).level;
    } else {
        return false;
    }
}

pub fn actualLevel(current_level: u4, total_experience: u16) u4 {
    var level = current_level;
    while (g.meta.Levels[level - 1] < total_experience) {
        level += 1;
    }
    return level;
}

/// Adds exp to the player's Experience. If it leads to level up,
/// increases the player level, updates the LevelUp component for the player,
/// and return `true`. Otherwise returns `false`.
pub fn addExperience(registry: *g.Registry, player: g.Entity, exp: u16) !bool {
    const experience = registry.getUnsafe(player, c.Experience);
    const level_before = experience.level;
    experience.experience +|= exp;
    experience.level = actualLevel(experience.level, experience.experience);
    if (experience.level > level_before) {
        const level_up = try registry.getOrSet(player, c.LevelUp, .{ .last_handled_level = level_before });
        level_up.last_handled_level = @min(level_up.last_handled_level, level_before);
        return true;
    } else {
        return false;
    }
}

pub fn initialHealth(constitution: i4) c.Health {
    const constitution_factor = (@as(f32, @floatFromInt(constitution)) * 0.6 + 4.4) / 4.0;
    return .init(@intFromFloat(@round(constitution_factor * 20)));
}

pub fn movePointsForAction(registry: *const g.Registry, actor: g.Entity, _: g.Action) g.MovePoints {
    // TODO: return different mp for attacks
    return registry.getUnsafe(actor, c.Speed).move_points;
}

/// Adds a random modification to the entity.
/// The value can be taken randomly from the range [`min`, `max`] if the effect is passed explicitly,
/// or the effect selecting randomly.
/// Finally, the codepoint of the entity is changed to its "unknown" version.
pub fn modifyEntity(
    registry: *g.Registry,
    rand: std.Random,
    entity: g.Entity,
    unknown_codepoint: g.Codepoint,
    min: i8,
    max: i8,
    modified_effect: ?c.Effects.Type,
) !void {
    const value = rand.intRangeAtMost(i8, min, max);
    const effect: c.Effects.Type = if (modified_effect) |eff|
        eff
    else
        c.Effects.chooseRandomType(rand);
    const modification = try registry.getOrSet(entity, c.Modification, .{ .modificators = .initFull(0) });
    modification.modificators.getPtr(effect).?.* +|= value;
    log.debug("Add modificator {t} = {d} for {d}", .{ effect, value, entity.id });
    try registry.set(entity, c.Sprite{ .codepoint = unknown_codepoint });
}

/// Writes an actual name of the entity according to its "known" status in the journal
/// to the `dest` buffer and returns a slice with result.
pub fn printActualName(dest: []u8, journal: g.Journal, entity: g.Entity) ![]u8 {
    if (g.meta.getPotionType(journal.registry, entity)) |potion_type| {
        if (journal.unknownPotionColor(potion_type)) |color|
            return try std.fmt.bufPrint(dest, "A {t} potion", .{color});
    }
    if (journal.registry.get(entity, c.Ammunition)) |ammo| {
        return try std.fmt.bufPrint(
            dest,
            "{s} {d}",
            .{ try rawName(journal.registry, entity), ammo.amount },
        );
    }
    return try std.fmt.bufPrint(dest, "{s}", .{try rawName(journal.registry, entity)});
}

pub fn rawName(registry: *g.Registry, entity: g.Entity) ![]const u8 {
    if (registry.get(entity, c.Description)) |description| {
        return g.components.Description.Preset.fields.get(description.preset).name;
    } else {
        return "Unknown";
    }
}

pub fn describePlayer(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    player: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get6(player, c.Experience, c.Health, c.Hunger, c.Stats, c.Skills, c.Equipment)) |tuple| {
        const experience, const health, const hunger, const stats, const skills, const equipment = tuple;
        try describeProgression(alloc, experience.level, experience.experience, text_area);
        _ = try text_area.addEmptyLine(alloc);
        try describeHealth(alloc, health, text_area);
        _ = try text_area.addEmptyLine(alloc);
        if (@intFromEnum(hunger.level()) > 0) {
            const line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line, "{f}", .{hunger.level()});
            _ = try text_area.addEmptyLine(alloc);
        }
        try describeEquipedItems(alloc, journal, equipment, text_area);
        _ = try text_area.addEmptyLine(alloc);
        try describeSkills(alloc, skills, text_area);
        _ = try text_area.addEmptyLine(alloc);
        try describeStats(alloc, stats, text_area);
    }
}

/// Writes progression to a text area.
/// ```
/// Level: {d}
/// Experience: {d}/{d}
/// ```
pub fn describeProgression(
    alloc: std.mem.Allocator,
    level: u4,
    experience: u16,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Level: {d}", .{level});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(
        line,
        "Experience: {d}/{d}",
        .{ experience, g.meta.experienceToNextLevel(level) },
    );
}

/// Writes the current and maximal amount of health points to a text area.
/// ```
/// HP: {d}/{d}
/// ```
pub fn describeHealth(
    alloc: std.mem.Allocator,
    health: *const c.Health,
    text_area: *g.windows.TextArea,
) !void {
    const line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Health: {d}/{d}", .{ health.current_hp, health.max });
}

/// Writes skills to a text area:
/// ```
/// Skills:
///   Weapon Mastery     0
///   Mechanics          0
///   Stealth            0
///   Echo of knowledge  0
/// ```
pub fn describeSkills(
    alloc: std.mem.Allocator,
    skills: *const c.Skills,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Skills:", .{});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Weapon Mastery:     {d}", .{skills.values.get(.weapon_mastery)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Mechanics:          {d}", .{skills.values.get(.mechanics)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Stealth:            {d}", .{skills.values.get(.stealth)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Echo of knowledge:  {d}", .{skills.values.get(.echo_of_knowledge)});
}

/// Writes stats to a text area.
/// ```
/// Stats:
///   Strength           0
///   Dexterity          0
///   Perception         0
///   Intelligence       0
///   Constitution       0
/// ```
pub fn describeStats(
    alloc: std.mem.Allocator,
    stats: *const c.Stats,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Stats:", .{});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Strength:           {d}", .{stats.strength});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Dexterity:          {d}", .{stats.dexterity});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Perception:         {d}", .{stats.perception});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Intelligence:       {d}", .{stats.intelligence});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Constitution:       {d}", .{stats.constitution});
}

/// Builds an actual description of the entity, and writes it to the text_area.
/// **Note**, that to describe the player the `describePlayer` method should be used.
pub fn describeEntity(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe an entity {d}", .{entity.id});
    // Write the text of description at first:
    try writeActualDescription(alloc, journal, entity, text_area);
    // Then write properties:
    if (g.meta.isItem(journal.registry, entity)) {
        try describeItem(alloc, journal, entity, text_area);
    } else if (g.meta.getEnemyType(journal.registry, entity)) |enemy_type| {
        try describeEnemy(alloc, journal, entity, enemy_type, text_area);
    }
}

/// Writes the known description of an entity.
/// Known and unknown items and enemies have different descriptions.
fn writeActualDescription(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (g.meta.getPotionType(journal.registry, entity)) |potion_type| {
        if (journal.unknownPotionColor(potion_type)) |color| {
            var line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line, "A swirling liquid of {t} color", .{color});
            line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line, "rests in a vial.", .{});
            return;
        }
    }
    const description = if (journal.registry.get(entity, c.Description)) |descr|
        g.components.Description.Preset.fields.get(descr.preset).description
    else
        &.{};
    for (description) |str| {
        var line = try text_area.addEmptyLine(alloc);
        @memmove(line[0..str.len], str);
    }
}

pub fn describeItem(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe an item {d}", .{entity.id});
    if (journal.registry.get(entity, c.Consumable)) |consumable| {
        _ = try text_area.addEmptyLine(alloc);
        try describeEffects(
            alloc,
            journal,
            entity,
            consumable.effects,
            "Effects",
            text_area,
        );

        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Calories: {d}", .{consumable.calories});
    }

    if (journal.registry.get(entity, c.Weapon)) |weapon| {
        _ = try text_area.addEmptyLine(alloc);
        try describeWeapon(alloc, journal, entity, weapon, text_area);
    }

    if (journal.registry.has(entity, c.Protection)) {
        _ = try text_area.addEmptyLine(alloc);
        try describeArmor(alloc, journal, entity, text_area);
    }

    if (journal.registry.get(entity, c.SourceOfLight)) |light| {
        _ = try text_area.addEmptyLine(alloc);
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Radius of light: {d}", .{light.radius});
    }

    if (journal.registry.get(entity, c.Weight)) |weight| {
        _ = try text_area.addEmptyLine(alloc);
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Weight: {d}", .{weight.value});
    }
}

/// Shows the damage of existed effects. If the weapon has a modification,
/// and is known, then the modification is applied to the effects, otherwise
/// a line with "It looks unusual(!)" text is appended.
///
/// Example of a known weapon:
/// ```
/// This is a primitive weapon.
/// Damage:
///   physical 3-5
///   fire 1-2
/// ```
/// Example of unknown weapon:
/// ```
/// This is a primitive weapon.
/// Damage:
///   physical 1-3
///   ?
///
/// It looks unusual(!)
/// ```
fn describeWeapon(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    entity: g.Entity,
    weapon: *const c.Weapon,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe a weapon {d} {any}", .{ entity.id, weapon });
    var line = try text_area.addEmptyLine(alloc);
    const article = if (weapon.class == .ancient) "an" else "a";
    _ = try std.fmt.bufPrint(line, "This is {s} {t} weapon.", .{ article, weapon.class });
    try describeEffects(alloc, journal, entity, weapon.damage, "Damage", text_area);

    if (weapon.max_distance > 1) {
        _ = try text_area.addEmptyLine(alloc);
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Max distance: {d}", .{weapon.max_distance});
    }
    if (!journal.isKnown(entity) and journal.registry.has(entity, c.Modification)) {
        _ = try text_area.addEmptyLine(alloc);
        line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..20], "It looks modified...");
    }
}

/// Shows the protection of the armor. If the armor has a modification,
/// and is known, then the modification is applied to the armor's effects, otherwise
/// a line with "It looks unusual(!)" text is appended.
///
/// Example of a known armor:
/// ```
/// Protection:
///   physical 3-5
///   fire 1-2
/// ```
/// Example of unknown armor:
/// ```
/// Protection:
///   physical 1-3
///   ?
///
/// It looks unusual(!)
/// ```
fn describeArmor(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    armor_entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe an armor {d}", .{armor_entity.id});
    try describeEffects(
        alloc,
        journal,
        armor_entity,
        journal.registry.getUnsafe(armor_entity, c.Protection).resistance,
        "Protection",
        text_area,
    );

    if (!journal.isKnown(armor_entity) and journal.registry.has(armor_entity, c.Modification)) {
        _ = try text_area.addEmptyLine(alloc);
        const line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..20], "It looks modified...");
    }
}

/// Adds lines with not zero effects to the `text_area`.
/// It check the knowing status of the entity and merge modifications to the effects before showing
/// their values.
///
/// Example for known source:
/// ```
/// <title>:
///   <effect type 1> <min>-<max>
///   <effect type 2> <min>-<max>
/// ...
/// ```
/// Example for unknown source:
/// ```
/// <title>:
///     ?
///     ?
/// ...
/// ```
/// Does nothing if a component `Effects` is not defined for the `entity`.
fn describeEffects(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    source: g.Entity,
    effects: c.Effects,
    title: []const u8,
    text_area: *g.windows.TextArea,
) !void {
    // make a copy to apply modifications
    var modified_effects: c.Effects = effects;
    const is_known_source = journal.isKnown(source);
    if (is_known_source) {
        if (journal.registry.get(source, c.Modification)) |modification| {
            modification.applyTo(&modified_effects);
        }
    }
    var line = try text_area.addEmptyLine(alloc);
    @memcpy(line[0..title.len], title);
    line[title.len] = ':';

    var itr = modified_effects.values.iterator();
    while (itr.next()) |tuple| {
        if (tuple.value.min == 0 and tuple.value.max == 0)
            continue;

        line = try text_area.addEmptyLine(alloc);
        if (is_known_source or tuple.key == .physical) {
            if (tuple.value.min == tuple.value.max) {
                _ = try std.fmt.bufPrint(line[2..], "{t} {d}", .{ tuple.key, tuple.value.min });
            } else {
                _ = try std.fmt.bufPrint(line[2..], "{t} {d}-{d}", .{ tuple.key, tuple.value.min, tuple.value.max });
            }
        } else {
            line[4] = '?';
        }
    }
}

pub fn describeEquipedItems(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    if (equipment.weapon) |weapon_id| {
        @memcpy(line[0..16], "Equiped weapon: ");
        _ = try printActualName(line[16..], journal, weapon_id);
        if (journal.registry.get(weapon_id, c.Weapon)) |weapon|
            try describeWeapon(alloc, journal, weapon_id, weapon, text_area);
    } else {
        _ = try std.fmt.bufPrint(line, "Equiped weapon: none", .{});
    }
    if (equipment.armor) |armor_id| {
        _ = try text_area.addEmptyLine(alloc);
        line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..15], "Equiped armor: ");
        _ = try printActualName(line[15..], journal, armor_id);
        try describeArmor(alloc, journal, armor_id, text_area);
    }
    const light_id, const light_radius = g.meta.getLight(journal.registry, equipment);
    if (light_id) |id| {
        _ = try text_area.addEmptyLine(alloc);
        line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..17], "Source of light: ");
        _ = try g.meta.printActualName(line[17..], journal, id);
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "       distance: {d}", .{light_radius});
    }
}

pub fn describeEnemy(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    enemy: g.Entity,
    enemy_type: g.meta.EnemyType,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.known_enemies.contains(enemy_type)) {
        if (journal.registry.get(enemy, c.Health)) |health| {
            _ = try text_area.addEmptyLine(alloc);
            try describeHealth(alloc, health, text_area);
        }
        if (journal.registry.get(enemy, c.Equipment)) |equipment| {
            try describeEquipedItems(alloc, journal, equipment, text_area);
        } else if (journal.registry.get(enemy, c.Weapon)) |weapon| {
            _ = try text_area.addEmptyLine(alloc);
            try describeEffects(alloc, journal, enemy, weapon.damage, "Damage", text_area);
        }
        if (journal.registry.get(enemy, c.Speed)) |speed| {
            _ = try text_area.addEmptyLine(alloc);
            // | Too slow | Slow | Not so fast | Fast | Very fast |
            //            |      |             |      |
            //          +10     +5           Normal  -5
            const diff: i16 = speed.move_points - c.Speed.default.move_points;
            const line = try text_area.addEmptyLine(alloc);
            if (diff >= 0) {
                if (diff < 5)
                    _ = try std.fmt.bufPrint(line, "Not too fast.", .{})
                else if (diff < 10)
                    _ = try std.fmt.bufPrint(line, "Slow.", .{})
                else
                    _ = try std.fmt.bufPrint(line, "Too slow.", .{});
            } else {
                if (diff > -5)
                    _ = try std.fmt.bufPrint(line, "Fast.", .{})
                else
                    _ = try std.fmt.bufPrint(line, "Very fast.", .{});
            }
        }
    } else {
        _ = try text_area.addEmptyLine(alloc);
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "Who knows what to expect from this", .{});
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "creature?", .{});
    }
}

test "Describe a player" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var registry = try g.Registry.init(&arena);
    const journal = try g.Journal.init(&registry, std.testing.random_seed);
    var text_area: g.windows.TextArea = .empty;

    const player = try registry.addNewEntity(try g.entities.player(alloc, prng.random(), .zeros, .zeros, .init(30)));
    const equipmen = registry.getUnsafe(player, c.Equipment);
    equipmen.weapon = try registry.addNewEntity(g.entities.presets.Items.fields.get(.torch).*);
    equipmen.armor = try registry.addNewEntity(g.entities.presets.Items.fields.get(.jacket).*);

    // when:
    try describePlayer(alloc, journal, player, &text_area);

    // then:
    try expectContent(text_area,
        \\Level: 1
        \\Experience: 0/500
        \\
        \\Health: 30/30
        \\
        \\Equiped weapon: Torch
        \\This is a primitive weapon.
        \\Damage:
        \\  physical 1
        \\  fire 1
        \\
        \\Equiped armor: Jacket
        \\Protection:
        \\  physical 0-5
        \\  fire 0-2
        \\
        \\Source of light: Torch
        \\       distance: 3
        \\
        \\Skills:
        \\  Weapon Mastery:     0
        \\  Mechanics:          0
        \\  Stealth:            0
        \\  Echo of knowledge:  0
        \\
        \\Stats:
        \\  Strength:           0
        \\  Dexterity:          0
        \\  Perception:         0
        \\  Intelligence:       0
        \\  Constitution:       0
    );
}

test "Describe an unknown rat" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.testing.random_seed);

    const id = try registry.addNewEntity(g.entities.presets.Enemies.get(.rat));
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Who knows what to expect from this
        \\creature?
    );
}

test "Describe a known rat" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    var journal = try g.Journal.init(&registry, std.testing.random_seed);

    const id = try registry.addNewEntity(g.entities.presets.Enemies.get(.rat));
    try journal.markEnemyAsKnown(g.meta.getEnemyType(&registry, id) orelse unreachable);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Health: 10/10
        \\
        \\Damage:
        \\  physical 1-3
        \\
        \\Not too fast.
    );
}

test "Describe a melee weapon" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.testing.random_seed);

    const id = try registry.addNewEntity(g.entities.presets.Items.fields.get(.torch).*);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning
        \\flame. Lasts until the  fire dies.
        \\It can be  used as a weapon out of
        \\despair.
        \\
        \\This is a primitive weapon.
        \\Damage:
        \\  physical 1
        \\  fire 1
        \\
        \\Radius of light: 3
        \\
        \\Weight: 20
    );
}

test "Describe a bow" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.testing.random_seed);

    const id = try registry.addNewEntity(g.entities.presets.Items.fields.get(.short_bow).*);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A compact bow. Quick to draw,
        \\quiet, and effective at short
        \\range.
        \\
        \\This is a tricky weapon.
        \\Damage:
        \\  physical 2-3
        \\
        \\Max distance: 5
        \\
        \\Weight: 50
    );
}

test "Describe an armor" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.testing.random_seed);

    const id = try registry.addNewEntity(g.entities.presets.Items.fields.get(.jacket).*);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A sturdy, time-worn leather jacket.
        \\Despite its worn  look, the  jacket
        \\offers     surprising    resilience
        \\against  scrapes   and  gives minor
        \\resistance to fire and heat.
        \\
        \\Protection:
        \\  physical 0-5
        \\  fire 0-2
        \\
        \\Weight: 10
    );
}

fn expectContent(actual: g.windows.TextArea, comptime expectation: []const u8) !void {
    errdefer {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        actual.write(&writer) catch unreachable;
        std.debug.print("\nThe actual content was:\n--------------\n{s}\n--------------", .{buffer});
    }
    var itr = std.mem.splitScalar(u8, expectation, '\n');
    var i: usize = 0;
    while (itr.next()) |line| {
        try std.testing.expectEqualStrings(line, std.mem.trimEnd(u8, &actual.lines.items[i], " \n"));
        i += 1;
    }
    if (i != actual.lines.items.len)
        return error.ActualLinesCountIsNotEqualToExpected;
}
