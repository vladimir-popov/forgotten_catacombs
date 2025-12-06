//! A full set of descriptions for all entities in the game.
//!
//! It also used as a tricky system of meta types.
//! Because of all entities must have a description, the easies way
//! to get a type for some entity is match its description `preset`
//! to a more precise enum that represents a type of the entity.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub const Description = struct {
    /// A short name of the entity.
    name: []const u8,

    // A line should have no more 36 symbols

    /// A short description of the entity.
    description: []const []const u8 = &.{},
};

pub const Archetypes = struct {
    pub const Enum = std.meta.FieldEnum(Archetypes);

    adventurer: Description = .{
        .name = "Adventurer",
        .description = &.{
            "You are  forever  in  search of new",
            "sensations. Your  main desire is to",
            "test  your strength  and  feel  the",
            "taste  of adventure.  You  have  no",
            "pronounced talents,  but no serious",
            "flaws   either.   Flexibility   and",
            "curiosity  make   you  a  versatile",
            "explorer of the forgotten catacombs",
        },
    },
    archeologist: Description = .{
        .name = "Archeologist",
        .description = &.{
            "",
        },
    },
    vandal: Description = .{
        .name = "Vandal",
        .description = &.{
            "",
        },
    },
    rogue: Description = .{
        .name = "Rogue",
        .description = &.{
            "",
        },
    },
};

// All descriptions for potions MUST be declared here
pub const Potions = struct {
    /// Enum of all potion types
    pub const Enum = std.meta.FieldEnum(Potions);

    healing_potion: Description = .{
        .name = "A healing potion",
        .description = &.{
            "A brew that glows faintly, as if",
            "mends alive. It warms your veins",
            "and your wounds instantly.",
        },
    },
    poisoning_potion: Description = .{
        .name = "A poison",
        .description = &.{
            "A vial filled with a thick, bitter",
            "liquid that smells of decay.",
        },
    },
    oil_potion: Description = .{
        .name = "Oil",
        .description = &.{
            "Glass bottle filled with viscous",
            "oil. Useful as lamp fuel.",
        },
    },
};

// All descriptions for enemies MUST be declared here
pub const Enemies = struct {
    /// Enum of all enemies types
    pub const Enum = std.meta.FieldEnum(Enemies);

    rat: Description = .{
        .name = "Rat",
        .description = &.{
            "A big, nasty rat with vicious eyes",
            "that thrives in dark corners and",
            "forgotten cellars.",
        },
    },
    wolf: Description = .{
        .name = "Wolf",
        .description = &.{
            "Wild predator. Its fur is smeared",
            "with blood, eyes glinting with",
            "hunger.",
        },
    },
};

pub const Skills = struct {
    pub const Enum = std.meta.FieldEnum(Skills);
    weapon_mastery: Description = .{
        .name = "Weapon Mastery",
        .description = &.{
            "Possessing this skill allows you",
            "to use any weapon more effectively",
            "and miss less often.",
        },
    },
    mechanics: Description = .{
        .name = "Mechanics",
        .description = &.{
            "Knowledge in the field of mechanics",
            "helps you pick locks and disarm",
            "traps.",
        },
    },
    stealth: Description = .{
        .name = "Stealth",
        .description = &.{
            "",
        },
    },
    echo_of_knowledge: Description = .{
        .name = "Echo of knowledge",
        .description = &.{
            "",
        },
    },
};

closed_door: Description = .{ .name = "Closed door" },
club: Description = .{
    .name = "Club",
    .description = &.{
        "A gnarled piece of wood, scarred",
        "from use. Deals blunt damage.",
        "Cheap and easy to use.",
    },
},
food_ration: Description = .{
    .name = "Food ration",
    .description = &.{
        "A compact bundle of preserved food.",
        "Bland and meager, yet designed to",
        "provide steady nourishment over a",
        "long period.",
    },
},
coctail_molotov: Description = .{
    .name = "Molotov cocktail",
    .description = &.{
        "A dark glass bottle sealed with a",
        "cloth wad soaked in fuel. When it",
        "shatters the dark liquid spatters",
        "and flames leap up",
    },
},
jacket: Description = .{
    .name = "Jacket",
    .description = &.{
        "A sturdy, time-worn leather jacket.",
        "Despite its worn look, the jacket",
        "offers surprising resilience",
        "against scrapes and gives minor",
        "resistance to fire and heat.",
    },
},
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
oil_lamp: Description = .{
    .name = "Oil lamp",
    .description = &.{
        "A simple metal lamp filled with",
        "oil, its flickering flame casts",
        "light into the darkest corners.",
    },
},
opened_door: Description = .{ .name = "Opened door" },
pickaxe: Description = .{
    .name = "Pickaxe",
    .description = &.{
        "Heavy tool for mining stone and ore",
        "Can double as a crude weapon.",
    },
},
pile: Description = .{
    .name = "Pile of items",
    .description = &.{
        "A heap of miscellaneous gear.",
        "Search it to see what’s useful.",
    },
},
player: Description = .{ .name = "You" },
scientist: Description = .{ .name = "Scientist" },
teleport: Description = .{ .name = "Teleport" },
torch: Description = .{
    .name = "Torch",
    .description = &.{
        "Wooden handle, cloth wrap, burning",
        "flame. Lasts until the fire dies.",
    },
},
traider: Description = .{ .name = "Traider" },
unknown_key: Description = .{ .name = "Unknown" },
wharf: Description = .{ .name = "Wharf" },

test "All descriptions should have lines with no more than 35 symbols" {
    var itr = g.presets.Descriptions.iterator();
    while (itr.next()) |description| {
        for (description.description) |line| {
            const len = try std.unicode.utf8CountCodepoints(line);
            std.testing.expect(len < 36) catch |err| {
                std.debug.print(
                    "Description {s} has too long line with {d} symbols:\n\"{s}\"\n",
                    .{ description.name, line.len, line },
                );
                return err;
            };
        }
    }
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
    if (journal.registry.get4(entity, c.Progression, c.Skills, c.Stats, c.Equipment)) |tuple| {
        try describePlayer(alloc, journal, tuple[0], tuple[1], tuple[2], tuple[3], text_area);
        return;
    }
    // Write the text of description at first:
    try writeActualDescription(journal, alloc, entity, text_area);
    _ = try text_area.addEmptyLine(alloc);
    // Then write properties:
    if (g.meta.isItem(journal.registry, entity)) {
        try describeItem(journal, alloc, entity, text_area);
    } else if (g.meta.isEnemy(journal.registry, entity)) |enemy_type| {
        try describeEnemy(journal, alloc, entity, enemy_type, text_area);
    }
}

fn describePlayer(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    progression: *const c.Progression,
    skills: *const c.Skills,
    stats: *const c.Stats,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    _ = try text_area.addEmptyLine(alloc);
    try g.descriptions.describeProgression(alloc, progression.*, text_area);
    _ = try text_area.addEmptyLine(alloc);
    try describeEquipment(alloc, journal, equipment, text_area);
    _ = try text_area.addEmptyLine(alloc);
    try g.descriptions.describeSkills(alloc, skills, text_area);
    _ = try text_area.addEmptyLine(alloc);
    try g.descriptions.describeStats(alloc, stats, text_area);
}

/// Writes progression to a text area.
/// ```
/// Level: {d}
/// Experience: {d}/{d}
/// ```
pub fn describeProgression(
    alloc: std.mem.Allocator,
    progression: c.Progression,
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
    _ = try text_area.addEmptyLine(alloc);
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

pub fn describeItem(
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

pub fn describeEnemy(
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
            try describeEquipment(alloc, journal, equipment, text_area);
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

pub fn describeEquipment(
    alloc: std.mem.Allocator,
    journal: g.Journal,
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
    _ = try std.fmt.bufPrint(
        line[1..],
        "Radius of light: {d}",
        .{g.meta.getRadiusOfLight(journal.registry, equipment)},
    );
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
