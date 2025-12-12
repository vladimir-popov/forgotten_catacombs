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
            "explorer     of     the   forgotten",
            "catacombs.",
        },
    },
    archeologist: Description = .{
        .name = "Archeologist",
        .description = &.{
            "You live for  discoveries.  Nothing",
            "holds more value for  you than lost",
            "knowledge  and  the  secrets of the",
            "past. Every new find is your reward",
            "and for  it,  you are ready to take",
            "risks others avoid.  Your  physical",
            "condition leaves much to be desired",
            "movements are clumsy, but your mind",
            "is  sharp  and  your heart knows no",
            "fear.  Who  knows  -  perhaps  your",
            "knowledge and curiosity will become",
            "the  key  to  the  secrets  of  the",
            "forgotten catacombs.",
        },
    },
    vandal: Description = .{
        .name = "Vandal",
        .description = &.{
            "You  are  a   straightforward   and",
            "simple    person.   Philosophy   or",
            "science  do  not interest you; only",
            "the thirst  for  profit drives you.",
            "You stop  at  nothing  for wealth -",
            "destruction, fighting, or risk  are",
            "merely tools  to achieve your goal.",
            "Your strength  and  endurance allow",
            "you to  survive where others break,",
            "and your physical power makes you a",
            "dangerous opponent in close combat.",
        },
    },
    rogue: Description = .{
        .name = "Rogue",
        .description = &.{
            "You are agile and cunning.Dexterity",
            "matters more to you than  strength.",
            "Direct  confrontations are not your",
            "way:  why  take  risks when you can",
            "quietly take what you need? Legends",
            "of forgotten artifacts of the  past",
            "lure you with the promise of wealth",
            "Every lock, every trap is merely an",
            "obstacle on your path to your goal:",
            "to  become   the   owner   of  lost",
            "technologies that will sustain  you",
            "for the rest of your life.",
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
            "Possessing this skill  allows  you",
            "to use any weapon more effectively",
            "and miss less often.",
        },
    },
    mechanics: Description = .{
        .name = "Mechanics",
        .description = &.{
            "Knowledge in the field of mechanics",
            "helps  you  pick  locks  and disarm",
            "traps.",
        },
    },
    stealth: Description = .{
        .name = "Stealth",
        .description = &.{
            "Stealth  is the ability  to  remain",
            "unseen — to stay out  of sight  and",
            "avoid    waking    the   slumbering",
            "inhabitants of the dungeons.",
        },
    },
    echo_of_knowledge: Description = .{
        .name = "Echo of knowledge",
        .description = &.{
            "The character possesses  an  innate",
            "understanding  of  the sciences and",
            "technologies of past civilizations.",
            "This    ability   allows   you   to",
            "comprehend  devices  and  artifacts",
            "from  the past and to apply them in",
            "practice.",
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
    return if (journal.unknownPotionColor(entity)) |color|
        try std.fmt.bufPrint(dest, "A {t} potion", .{color})
    else if (journal.registry.get(entity, c.Description)) |description|
        try std.fmt.bufPrint(dest, "{s}", .{g.presets.Descriptions.values.get(description.preset).name})
    else
        try std.fmt.bufPrint(dest, "Unknown", .{});
}

pub fn describePlayer(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    player: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get5(player, c.Experience, c.Health, c.Stats, c.Skills, c.Equipment)) |tuple| {
        const experience, const health, const stats, const skills, const equipment = tuple;
        try describeProgression(alloc, experience.level, experience.experience, text_area);
        _ = try text_area.addEmptyLine(alloc);
        try describeHealth(alloc, health, text_area);
        _ = try text_area.addEmptyLine(alloc);
        try describeEquipment(alloc, journal, equipment, text_area);
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
    _ = try std.fmt.bufPrint(line, "Health: {d}/{d}", .{ health.current, health.max });
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
    // Write the text of description at first:
    try writeActualDescription(alloc, journal, entity, text_area);
    _ = try text_area.addEmptyLine(alloc);
    // Then write properties:
    if (g.meta.isItem(journal.registry, entity)) {
        try describeItem(alloc, journal, entity, text_area);
    } else if (g.meta.isEnemy(journal.registry, entity)) |enemy_type| {
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
    if (journal.unknownPotionColor(entity)) |color| {
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
    alloc: std.mem.Allocator,
    journal: g.Journal,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    try describeEffects(
        alloc,
        journal,
        entity,
        if (g.meta.isWeapon(journal.registry, entity)) "Damage" else "Effects",
        text_area,
    );

    if (journal.registry.get(entity, c.SourceOfLight)) |light| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Radius of light: {d}", .{light.radius});
    }
    if (journal.registry.get(entity, c.Weight)) |weight| {
        const line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "Weight: {d}", .{weight.value});
    }
}

pub fn describeEquipment(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine(alloc);
    if (equipment.weapon) |weapon| {
        @memcpy(line[0..16], "Equiped weapon: ");
        _ = try printName(line[16..], journal, weapon);
        try describeEffects(alloc, journal, weapon, "Damage", text_area);
    } else {
        _ = try std.fmt.bufPrint(line, "Equiped weapon: none", .{});
    }
    const light_id, const light_radius = g.meta.getLight(journal.registry, equipment);
    if (light_id) |id| {
        _ = try text_area.addEmptyLine(alloc);
        line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..17], "Source of light: ");
        _ = try g.descriptions.printName(line[17..], journal, id);
        line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line, "       distance: {d}", .{light_radius});
    }
}

/// Example for known source or physical damage:
/// ```
/// <title>:
/// <pad><effect_type> <min>-<max>
/// ```
/// Example for unknown source:
/// ```
/// <title>:
/// <pad>?
/// ```
fn describeEffects(
    alloc: std.mem.Allocator,
    journal: g.Journal,
    source: g.Entity,
    title: []const u8, // Damage|Effects
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get(source, c.Effects)) |effects| {
        if (effects.len == 0 or journal.unknownPotionColor(source) != null) return;

        const is_known_source = journal.isKnown(source);
        var line = try text_area.addEmptyLine(alloc);
        @memcpy(line[0..title.len], title);
        line[title.len] = ':';

        for (effects.items()) |effect| {
            line = try text_area.addEmptyLine(alloc);
            if (is_known_source or effect.effect_type == .physical)
                _ = try std.fmt.bufPrint(line[2..], "{t} {d}-{d}", .{ effect.effect_type, effect.min, effect.max })
            else
                line[4] = '?';
        }
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
            try describeHealth(alloc, health, text_area);
        }
        if (journal.registry.get(enemy, c.Equipment)) |equipment| {
            try describeEquipment(alloc, journal, equipment, text_area);
        } else {
            try describeEffects(alloc, journal, enemy, "Damage", text_area);
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

test "Describe player" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var registry = try g.Registry.init(alloc);
    const journal = try g.Journal.init(alloc, &registry, std.testing.random_seed);
    var text_area: g.windows.TextArea = .empty;

    const player = try registry.addNewEntity(try g.entities.player(alloc, .zeros, .zeros, .init(30)));
    const equipmen = registry.getUnsafe(player, c.Equipment);
    equipmen.weapon = try registry.addNewEntity(g.presets.Items.values.get(.torch).*);

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
        \\Damage:
        \\  physical 2-3
        \\  burning 1-1
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
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, std.testing.random_seed);
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
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
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, std.testing.random_seed);
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.entities.rat(.{ .row = 1, .col = 1 }));
    try journal.markEnemyAsKnown(id);
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
        \\Damage:
        \\  physical 1-3
        \\
        \\Not too fast.
    );
}

test "Describe a torch" {
    // given:
    var registry = try g.Registry.init(std.testing.allocator);
    defer registry.deinit();
    var journal = try g.Journal.init(std.testing.allocator, &registry, std.testing.random_seed);
    defer journal.deinit(std.testing.allocator);

    const id = try registry.addNewEntity(g.presets.Items.values.get(.torch).*);
    var text_area: g.windows.TextArea = .empty;
    defer text_area.deinit(std.testing.allocator);

    // when:
    try describeEntity(std.testing.allocator, journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning
        \\flame. Lasts until the fire dies.
        \\
        \\Damage:
        \\  physical 2-3
        \\  burning 1-1
        \\Radius of light: 3
        \\Weight: 20
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
