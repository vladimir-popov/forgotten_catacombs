//! Set of helpers to get an information about entities from a registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Error = error{
    DamageIsNotSpecified,
};

pub const PotionType = g.descriptions.potions.Enum;
pub const EnemyType = g.descriptions.enemies.Enum;
pub const PlayerArchetype = g.descriptions.player_archetypes.Enum;
pub const Skill = g.descriptions.skills.Enum;

/// Any entity with weight is item.
pub inline fn isItem(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

/// Any entity with damage is weapon.
pub inline fn isWeapon(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Damage);
}

/// Any entity with a `SourceOfLight` is a light.
pub inline fn isLight(registry: *const g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.SourceOfLight);
}

/// Returns a type of a potion if it has description preset from appropriate namespace.
pub inline fn isPotion(registry: *const g.Registry, entity: g.Entity) ?PotionType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(PotionType, @tagName(descr.preset))
    else
        null;
}

/// Returns a type of an enemy if it has description preset from appropriate namespace.
pub inline fn isEnemy(registry: *const g.Registry, entity: g.Entity) ?EnemyType {
    return if (registry.get(entity, c.Description)) |descr|
        std.meta.stringToEnum(EnemyType, @tagName(descr.preset))
    else
        null;
}

/// Only weapon and source of light can be equipped.
pub fn canEquip(registry: *const g.Registry, item: g.Entity) bool {
    return isWeapon(registry, item) or isLight(registry, item);
}

/// Returns the radius of the light as a maximal radius of all equipped sources of the light.
pub fn getRadiusOfLight(registry: *const g.Registry, equipment: *const c.Equipment) f16 {
    if (equipment.light) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol.radius;
        }
    }
    return 1.5;
}

/// Returns a `Damage` component and optional `Effect` of the currently used weapon.
/// The `actor` must be a player or an enemy,  otherwise the `DamageIsNotSpecified` will be returned.
pub fn getDamage(registry: *const g.Registry, actor: g.Entity) Error!struct { *c.Damage, ?*c.Effect } {
    // creatures can damage directly (rat's tooth as example)
    if (registry.get(actor, c.Damage)) |damage| {
        return .{ damage, registry.get(actor, c.Effect) };
    }
    if (registry.get(actor, c.Equipment)) |equipment| {
        if (equipment.weapon) |weapon| {
            if (registry.get(weapon, c.Damage)) |damage| {
                return .{ damage, registry.get(weapon, c.Effect) };
            }
        }
    }
    return error.DamageIsNotSpecified;
}

/// Writes an actual name of the entity according to its "known" status in the journal
/// to the `dest` buffer and returns a slice with result.
pub fn printName(dest: []u8, journal: g.Journal, entity: g.Entity) ![]u8 {
    return if (journal.isUnknownPotion(entity)) |color|
        try std.fmt.bufPrint(dest, "A {t} potion", .{color})
    else if (journal.registry.get(entity, c.Description)) |description|
        try std.fmt.bufPrint(dest, "{s}", .{g.presets.Descriptions.values.get(description.preset).name})
    else
        try std.fmt.bufPrint(dest, "Unknown", .{});
}

/// Builds an actual description of the entity, and writes it to the text_area.
pub fn describe(
    journal: g.Journal,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get3(entity, c.Progression, c.Stats, c.Skills)) |tuple| {
        try describePlayer(alloc, tuple[0], tuple[1], tuple[2], text_area);
        return;
    }
    // Write the text of description at first:
    try writeActualDescription(journal, alloc, entity, text_area);
    _ = try text_area.addEmptyLine(alloc);
    // Then write properties:
    if (isItem(journal.registry, entity)) {
        try describeItem(journal, alloc, entity, text_area);
    } else if (isEnemy(journal.registry, entity)) |enemy_type| {
        try describeEnemy(journal, alloc, entity, enemy_type, text_area);
    }
}

/// Level: {d}
/// Experience: {d}/{d}
///
/// Skills:
///   Weapon Mastery     0
///   Mechanics          0
///   Stealth            0
///   Echo of knowledge  0
///
/// Stats:
///   Strength           0
///   Dexterity          0
///   Perception         0
///   Intelligence       0
///   Constitution       0
pub fn describePlayer(
    alloc: std.mem.Allocator,
    progression: *const c.Progression,
    stats: *const c.Stats,
    skills: *const c.Skills,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Level: {d}", .{progression.level});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(
        line,
        "Experience: {d}/{d}",
        .{ progression.experience, progression.experienceToNextLevel() },
    );
    _ = try text_area.addEmptyLine(alloc);

    // Describe skills:
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "Skills:", .{});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Weapon Mastery:     {d}", .{skills.values.get(.weapon_mastery)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Mechanics:          {d}", .{skills.values.get(.mechanics)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Stealth:            {d}", .{skills.values.get(.stealth)});
    line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line, "  Echo of knowledge:  {d}", .{skills.values.get(.echo_of_knowledge)});
    _ = try text_area.addEmptyLine(alloc);

    // Describe stats:
    line = try text_area.addEmptyLine(alloc);
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

/// Writes the known description of an entity.
/// Known and unknown items and enemies have different descriptions.
fn writeActualDescription(
    journal: g.Journal,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.isUnknownPotion(entity)) |color| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "A swirling liquid of {t} color", .{color});
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "rests in a vial.", .{});
    } else {
        const description = if (journal.registry.get(entity, c.Description)) |descr|
            g.presets.Descriptions.values.get(descr.preset).description
        else
            &.{};
        for (description) |str| {
            var line = try text_area.addEmptyLine(alloc);
            @memmove(line[0..str.len], str);
        }
    }
}

fn describeItem(
    journal: g.Journal,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get(entity, c.Damage)) |damage| {
        try describeDamage(alloc, damage, text_area, 0);
    }
    if (journal.isKnown(entity)) {
        if (journal.registry.get(entity, c.Effect)) |effect| {
            try describeEffect(alloc, effect, text_area, 0);
        }
    }
    if (journal.registry.get(entity, c.SourceOfLight)) |light| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Radius of light: {d}", .{light.radius});
    }
    if (journal.registry.get(entity, c.Weight)) |weight| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Weight: {d}", .{weight.value});
    }
}

fn describeEnemy(
    journal: g.Journal,
    alloc: std.mem.Allocator,
    enemy: g.Entity,
    enemy_type: g.meta.EnemyType,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.known_enemies.contains(enemy_type)) {
        if (journal.registry.get(enemy, c.Health)) |health| {
            const line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line, "Health: {d}/{d}", .{ health.current, health.max });
        }
        if (journal.registry.get(enemy, c.Equipment)) |equipment| {
            try describeEquipment(journal, alloc, equipment, text_area);
        } else if (journal.registry.get(enemy, c.Damage)) |damage| {
            try describeDamage(alloc, damage, text_area, 0);
            if (journal.registry.get(enemy, c.Effect)) |effect| {
                try describeEffect(alloc, effect, text_area, 0);
            }
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
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "Who knows what to expect from this", .{});
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[0..], "creature?", .{});
    }
}

fn describeEquipment(
    journal: g.Journal,
    alloc: std.mem.Allocator,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    if (equipment.weapon) |weapon| {
        var line = try text_area.addEmptyLine(alloc);
        @memcpy(line[1..17], "Equiped weapon: ");
        _ = try printName(line[17..], journal, weapon);
        if (journal.registry.get(weapon, c.Damage)) |damage| {
            try describeDamage(alloc, damage, text_area, 3);
        }
        if (journal.registry.get(weapon, c.Effect)) |effect| {
            try describeEffect(alloc, effect, text_area, 3);
        }
    }
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line[1..], "Radius of light: {d}", .{getRadiusOfLight(journal.registry, equipment)});
}

fn describeDamage(
    alloc: std.mem.Allocator,
    damage: *const c.Damage,
    text_area: *g.windows.TextArea,
    pad: usize,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line[pad..], "Damage: {t} {d}-{d}", .{ damage.damage_type, damage.min, damage.max });
}

fn describeEffect(
    alloc: std.mem.Allocator,
    effect: *const c.Effect,
    text_area: *g.windows.TextArea,
    pad: usize,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    _ = try std.fmt.bufPrint(line[pad..], "Effect: {t} {d}-{d}", .{ effect.effect_type, effect.min, effect.max });
}

pub fn statsFromArchetype(archetype: PlayerArchetype) c.Stats {
    return switch (archetype) {
        .adventurer => .init(0, 0, 0, 0, 0),
        .archeologist => .init(-2, 0, 1, 2, 0),
        .vandal => .init(2, 0, -1, -1, 2),
        .rogue => .init(-1, 2, 1, 0, -1),
    };
}

test "Describe an unknown rat" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, prng.random());
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(journal, std.testing.allocator, id, &text_area);

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
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, prng.random());
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
    try journal.markEnemyAsKnown(id);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(journal, std.testing.allocator, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Health: 10/10
        \\Damage: physical 1-3
        \\
        \\Not too fast.
    );
}

test "Describe a torch" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, prng.random());
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.presets.Items.values.get(.torch).*);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describe(journal, std.testing.allocator, id, &text_area);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning
        \\flame. Lasts until the fire dies.
        \\
        \\Damage: physical 2-3
        \\Effect: burning 1-1
        \\Radius of light: 3
        \\Weight: 20
    );
}

fn expectContent(actual: g.windows.TextArea, comptime expectation: []const u8) !void {
    errdefer {
        var buffer: [1024]u8 = undefined;
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
}
