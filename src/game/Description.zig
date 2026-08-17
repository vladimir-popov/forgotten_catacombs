const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;

const log = std.log.scoped(.description);

/// A short name of the entity.
name: []const u8,

// A line should have no more 36 symbols

/// A short description of the entity.
description: []const []const u8 = &.{},

pub fn rawName(registry: *g.Registry, entity: g.Entity) ![]const u8 {
    if (registry.get(entity, c.Description)) |description| {
        return g.components.Description.Preset.fields.get(description.preset).name;
    } else {
        return "Unknown";
    }
}

pub const ActualNameFormatter = struct {
    journal: g.Journal,
    entity: g.Entity,

    pub fn format(self: ActualNameFormatter, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.journal.registry.get(self.entity, c.Potion)) |potion| {
            if (self.journal.unknownPotionColor(potion.*)) |color|
                return try writer.print("A {t} potion", .{color});
        }
        if (self.journal.registry.get(self.entity, c.Ammunition)) |ammo| {
            return try writer.print(
                "{s} {d}",
                .{ try g.Description.rawName(self.journal.registry, self.entity), ammo.amount },
            );
        }
        if (self.journal.registry.get(self.entity, c.Description)) |description| {
            if (description.preset == .gold_pile)
                return try writer.print(
                    "{s} {d}",
                    .{
                        g.components.Description.Preset.fields.get(description.preset).name,
                        self.journal.registry.getUnsafe(self.entity, c.Wallet).money,
                    },
                );
        }
        return try writer.writeAll(try g.Description.rawName(self.journal.registry, self.entity));
    }
};

pub fn actualNameFormatter(journal: g.Journal, entity: g.Entity) ActualNameFormatter {
    return .{ .journal = journal, .entity = entity };
}

/// Writes an actual name of the entity according to its "known" status in the journal
/// to the `dest` buffer and returns a slice with result.
pub fn printActualName(dest: []u8, journal: g.Journal, entity: g.Entity) ![]u8 {
    return try std.fmt.bufPrint(dest, "{f}", .{actualNameFormatter(journal, entity)});
}

pub fn describePlayer(
    journal: g.Journal,
    player: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get6(player, c.Experience, c.Health, c.Hunger, c.Stats, c.Skills, c.Equipment)) |tuple| {
        const experience, const health, const hunger, const stats, const skills, const equipment = tuple;
        try describeProgression(experience.level, experience.experience, text_area);
        _ = try text_area.addEmptyLine();
        try describeHealth(health, text_area);
        _ = try text_area.addEmptyLine();
        if (@intFromEnum(hunger.level()) > 0) {
            const line = try text_area.addEmptyLine();
            _ = try std.fmt.bufPrint(line, "{f}", .{hunger.level()});
            _ = try text_area.addEmptyLine();
        }
        try describeEquipedItems(journal, equipment, text_area);
        _ = try text_area.addEmptyLine();
        try describeSkills(skills, text_area);
        _ = try text_area.addEmptyLine();
        try describeStats(stats, text_area);
    }
}

/// Writes progression to a text area.
/// ```
/// Level: {d}
/// Experience: {d}/{d}
/// ```
pub fn describeProgression(
    level: u4,
    experience: u16,
    text_area: *g.windows.TextArea,
) !void {
    try text_area.printLineFmt("Level: {d}", .{level});
    try text_area.printLineFmt(
        "Experience: {d}/{d}",
        .{ experience, g.meta.experienceToNextLevel(level) },
    );
}

/// Writes the current and maximal amount of health points to a text area.
/// ```
/// HP: {d}/{d}
/// ```
pub fn describeHealth(health: *const c.Health, text_area: *g.windows.TextArea) !void {
    try text_area.printLineFmt("Health: {d}/{d}", .{ health.current_hp, health.max });
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
    skills: *const c.Skills,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "Skills:", .{});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Weapon Mastery:     {d}", .{skills.values.get(.weapon_mastery)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Mechanics:          {d}", .{skills.values.get(.mechanics)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Stealth:            {d}", .{skills.values.get(.stealth)});
    line = try text_area.addEmptyLine();
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
    stats: *const c.Stats,
    text_area: *g.windows.TextArea,
) !void {
    var line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "Stats:", .{});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Strength:           {d}", .{stats.get(.strength)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Dexterity:          {d}", .{stats.get(.dexterity)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Perception:         {d}", .{stats.get(.perception)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Intelligence:       {d}", .{stats.get(.intelligence)});
    line = try text_area.addEmptyLine();
    _ = try std.fmt.bufPrint(line, "  Constitution:       {d}", .{stats.get(.constitution)});
}

pub fn describeEnemy(
    journal: g.Journal,
    enemy: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    try writeDescription(journal, enemy, text_area);
    _ = try text_area.addEmptyLine();
    const enemy_type = g.meta.getEnemyType(journal.registry, enemy) orelse @panic("Unknown enemy");
    if (journal.known_enemies.contains(enemy_type)) {
        if (journal.registry.get(enemy, c.Health)) |health| {
            try describeHealth(health, text_area);
        }
        if (journal.registry.get(enemy, c.Weapon)) |weapon| {
            _ = try text_area.addEmptyLine();
            try describeWeapon(journal, enemy, weapon, true, text_area);
        }
        if (journal.registry.get(enemy, c.Armor)) |armor| {
            _ = try text_area.addEmptyLine();
            try describeArmor(journal, enemy, armor, true, text_area);
        }
        try describeModificationsAndTraits(journal.registry, enemy, text_area);

        if (journal.registry.get(enemy, c.Speed)) |speed| {
            _ = try text_area.addEmptyLine();
            if (speed.moving_speed > c.Speed.default.moving_speed)
                try text_area.printLine("Fast.")
            else if (speed.moving_speed < c.Speed.default.moving_speed)
                try text_area.printLine("Slow.")
            else
                try text_area.printLine("Not too fast.");
        }
    } else {
        try text_area.printLine("Who knows what to expect from this");
        try text_area.printLine("creature?");
    }
}

/// Builds an actual description of an item, and writes it to the text_area.
/// `is_equipped` is used to mark a modified equipped and not equipped item in different ways
pub fn describeItem(
    journal: g.Journal,
    item: g.Entity,
    is_equipped: bool,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get(item, c.Potion)) |potion| {
        if (journal.unknownPotionColor(potion.*)) |color| {
            try text_area.printLineFmt("A swirling liquid of {t} color", .{color});
            try text_area.printLineFmt("rests in a vial.", .{});
        } else {
            try writeDescription(journal, item, text_area);
        }
    } else {
        try writeDescription(journal, item, text_area);
    }

    // Then write properties:
    if (journal.registry.get(item, c.Weapon)) |weapon| {
        _ = try text_area.addEmptyLine();
        try describeWeapon(journal, item, weapon, is_equipped, text_area);
    }
    if (journal.registry.get(item, c.Armor)) |armor| {
        _ = try text_area.addEmptyLine();
        try describeArmor(journal, item, armor, is_equipped, text_area);
    }
    if (journal.registry.get(item, c.Trap)) |trap| {
        _ = try text_area.addEmptyLine();
        try describeTrap(trap, text_area);
    }
    if (journal.registry.get(item, c.SourceOfLight)) |light| {
        _ = try text_area.addEmptyLine();
        try text_area.printLineFmt("Radius of light: {d}", .{light.radius});
    }
    if (journal.registry.get(item, c.Consumable)) |consumable| {
        _ = try text_area.addEmptyLine();
        try text_area.printLineFmt("Calories: {d}", .{consumable.calories});
    }
}

fn writeDescription(
    journal: g.Journal,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (journal.registry.get(entity, c.Description)) |descr| {
        const description = g.components.Description.Preset.fields.get(descr.preset).description;
        for (description) |str|
            try text_area.printLine(str);
    }
}

/// Shows the damage of existed effects.
///
/// Example of a melee weapon without modifications:
/// ```
/// This is a primitive weapon.
/// Damage: 3-5
/// ```
///
/// Example of a range weapon without modifications:
/// ```
/// This is a primitive weapon.
/// Damage: 3-5
/// Max range: 5
/// ```
///
/// Example of a known weapon with the fire effect and the poison modification:
/// ```
/// This is a primitive weapon.
/// Damage: 3-5
/// Effects:
///   fire
///   poison
/// ```
///
/// Example of a broken weapon with the fire effect and the poison modification:
/// ```
/// This is a primitive weapon.
/// Damage: 1-3
/// Effects:
///   fire
///   ?
///
/// It looks modified...
/// ```
///
/// Example of a broken weapon:
/// ```
/// This is a primitive weapon.
/// Damage: 3-5
/// Effects:
///   ?
///
/// IT'S BROKEN!
/// ```
fn describeWeapon(
    journal: g.Journal,
    entity: g.Entity,
    weapon: *const c.Weapon,
    is_equipped: bool,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe a weapon {d} {any}", .{ entity.id, weapon });

    if (weapon.class != .native) {
        const article = if (weapon.class == .ancient) "an" else "a";
        try text_area.printLineFmt("This is {s} {t} weapon.", .{ article, weapon.class });
    }
    try text_area.printLineFmt("Damage: {d}-{d}", .{ weapon.damage.min, weapon.damage.max });
    if (weapon.max_distance > 1) {
        try text_area.printLineFmt("Max range: {d}", .{weapon.max_distance});
    }

    const is_known = journal.isKnown(entity);
    const has_modifications = g.meta.hasModifications(journal.registry, entity);

    if (weapon.effects.count() > 0 or has_modifications) {
        _ = try text_area.addEmptyLine();
        try text_area.printLineFmt("Effects:", .{});
        var effs = weapon.effects.iterator();
        while (effs.next()) |effect| {
            try text_area.printLineFmt("  {t}", .{effect});
        }
        if (is_known) {
            try describeModificationsAndTraits(journal.registry, entity, text_area);
        } else {
            try text_area.printLineFmt("  ?", .{});
        }
    }

    if (has_modifications) {
        if ((is_known or is_equipped) and journal.registry.has(entity, c.Breakages)) {
            _ = try text_area.addEmptyLine();
            try text_area.printLineFmt("IT'S BROKEN!", .{});
        } else if (!is_known) {
            _ = try text_area.addEmptyLine();
            try text_area.printLineFmt("It looks modified...", .{});
        }
    }
}

/// Shows the protection of the armor.
///
/// Example of an armor without modifications:
/// ```
/// Protection: 3-5
/// ```
///
/// Example of a known armor with fire resistance modification:
/// ```
/// Protection: 3-5
/// Effects:
///   fire resistance
/// ```
///
/// Example of an unknown armor:
/// ```
/// Protection: 1-3
/// Effects:
///   ?
///
/// It looks modified...
/// ```
///
/// Example of a broken armor:
/// ```
/// Protection: 1-3
/// Effects:
///   ?
///
/// IT'S BROKEN!
/// ```
fn describeArmor(
    journal: g.Journal,
    entity: g.Entity,
    armor: *const c.Armor,
    is_equipped: bool,
    text_area: *g.windows.TextArea,
) !void {
    log.debug("Describe an armor {d} {any}", .{ entity.id, armor });

    try text_area.printLineFmt("Protection: {d}-{d}", .{ armor.protection.min, armor.protection.max });

    if (!g.meta.hasModifications(journal.registry, entity)) {
        return;
    }

    try text_area.printLine("Effects:");
    const is_known = journal.isKnown(entity);
    if (is_known) {
        try describeModificationsAndTraits(journal.registry, entity, text_area);
    } else {
        try text_area.printLine("  ?");
    }

    if ((is_known or is_equipped) and journal.registry.has(entity, c.Breakages)) {
        _ = try text_area.addEmptyLine();
        try text_area.printLineFmt("IT'S BROKEN!", .{});
    } else if (!is_known) {
        _ = try text_area.addEmptyLine();
        try text_area.printLineFmt("It looks modified...", .{});
    }
}

/// Describes item's modifications, or enemy's traits.
fn describeModificationsAndTraits(
    registry: *const g.Registry,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (registry.get(entity, c.Improvements)) |improvements| {
        var itr = improvements.modifications.iterator();
        while (itr.next()) |eff| {
            switch (eff) {
                .fire, .poison, .acid => try text_area.printLineFmt("  {t} resistance", .{eff}),
                .attack => try text_area.printLine("  attack speed increased"),
                .speed => try text_area.printLine("  speed increased"),
                else => try text_area.printLineFmt("  {t} +1", .{eff}),
            }
        }
    }
    if (registry.get(entity, c.Breakages)) |breakages| {
        var itr = breakages.modifications.iterator();
        while (itr.next()) |eff| {
            switch (eff) {
                .fire, .poison, .acid => try text_area.printLineFmt("  {t} weakness", .{eff}),
                .attack => try text_area.printLine("  attack speed decreased"),
                .speed => try text_area.printLine("  speed decreased"),
                else => try text_area.printLineFmt("  {t} -1", .{eff}),
            }
        }
    }
}

pub fn describeEquipedItems(
    journal: g.Journal,
    equipment: *const c.Equipment,
    text_area: *g.windows.TextArea,
) !void {
    if (equipment.weapon) |weapon_id| {
        try text_area.printLineFmt("Equiped weapon: {f}", .{actualNameFormatter(journal, weapon_id)});
        const weapon = journal.registry.getUnsafe(weapon_id, c.Weapon);
        try describeWeapon(journal, weapon_id, weapon, true, text_area);
    } else {
        try text_area.printLine("Equiped weapon: none");
    }
    _ = try text_area.addEmptyLine();
    if (equipment.armor) |armor_id| {
        try text_area.printLineFmt("Equiped armor: {f}", .{actualNameFormatter(journal, armor_id)});
        const armor = journal.registry.getUnsafe(armor_id, c.Armor);
        try describeArmor(journal, armor_id, armor, true, text_area);
    } else {
        try text_area.printLine("Equiped armor: none");
    }
    _ = try text_area.addEmptyLine();
    const light_id, const light_radius, const charge = g.meta.getLight(journal.registry, equipment);
    if (light_id) |id| {
        try text_area.printLineFmt("Source of light: {f}", .{actualNameFormatter(journal, id)});
        try text_area.printLineFmt("         radius: {d}", .{light_radius});
        try text_area.printLineFmt("         charge: {d}", .{charge});
    } else {
        try text_area.printLine("Source of light: none");
    }
}

pub fn describeTrap(
    trap: *const c.Trap,
    text_area: *g.windows.TextArea,
) !void {
    const label = switch (trap.power) {
        0 => "easy to disarm",
        1 => "have to tinker",
        2 => "risky to touch",
        3 => "God help me",
    };
    try text_area.printLineFmt("Difficulty: {s}", .{label});
}

test ActualNameFormatter {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var buffer: [64]u8 = undefined;
    var registry = try g.Registry.init(&arena);
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const entity = try registry.addNewEntity(g.entities.presets.Items.get(.torch));
    const raw_name = try g.Description.rawName(&registry, entity);

    // when:
    const actual_name = try std.fmt.bufPrint(&buffer, "{f}", .{g.Description.actualNameFormatter(journal, entity)});

    // then:
    try std.testing.expectEqualStrings(raw_name, actual_name);
}

test "Describe a player" {
    // given:
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var registry = try g.Registry.init(&arena);
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));
    var text_area: g.windows.TextArea = .initEmpty(alloc);

    const player = try registry.addNewEntity(try g.entities.player(alloc, prng.random(), .zeros, .zeros, .init(30)));

    // when:
    try describePlayer(journal, player, &text_area);

    // then:
    try expectContent(text_area,
        \\Level: 1
        \\Experience: 0/200
        \\
        \\Health: 30/30
        \\
        \\Equiped weapon: none
        \\
        \\Equiped armor: none
        \\
        \\Source of light: none
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
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const id = try registry.addNewEntity(g.entities.presets.Enemies.get(.rat));
    var text_area: g.windows.TextArea = .initEmpty(std.testing.allocator);
    defer text_area.deinit();

    // when:
    try describeEnemy(journal, id, &text_area);

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
    var journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const id = try registry.addNewEntity(g.entities.presets.Enemies.get(.rat));
    try journal.markEnemyAsKnown(g.meta.getEnemyType(&registry, id) orelse unreachable);
    var text_area: g.windows.TextArea = .initEmpty(std.testing.allocator);
    defer text_area.deinit();

    // when:
    try describeEnemy(journal, id, &text_area);

    // then:
    try expectContent(text_area,
        \\A big, nasty rat with vicious eyes
        \\that thrives in dark corners and
        \\forgotten cellars.
        \\
        \\Health: 10/10
        \\
        \\Damage: 3-8
        \\
        \\Not too fast.
    );
}

test "Describe a melee weapon" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const id = try registry.addNewEntity(g.entities.presets.Items.fields.get(.torch).*);
    var text_area: g.windows.TextArea = .initEmpty(std.testing.allocator);
    defer text_area.deinit();

    // when:
    try describeItem(journal, id, false, &text_area);

    // then:
    try expectContent(text_area,
        \\Wooden handle, cloth wrap, burning
        \\flame. Lasts until the  fire dies.
        \\It can be  used as a weapon out of
        \\despair.
        \\
        \\This is a primitive weapon.
        \\Damage: 1-1
        \\
        \\Effects:
        \\  fire
        \\
        \\Radius of light: 3
    );
}

test "Describe a bow" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const id = try registry.addNewEntity(g.entities.presets.Weapons.get(.short_bow));
    var text_area: g.windows.TextArea = .initEmpty(std.testing.allocator);
    defer text_area.deinit();

    // when:
    try describeItem(journal, id, false, &text_area);

    // then:
    try expectContent(text_area,
        \\A compact bow. Quick to draw,
        \\quiet, and effective at short
        \\range.
        \\
        \\This is a tricky weapon.
        \\Damage: 2-3
        \\Max range: 5
    );
}

test "Describe an armor" {
    // given:
    var game_state_arena: g.GameStateArena = .init(std.testing.allocator);
    defer game_state_arena.deinit();

    var registry = try g.Registry.init(&game_state_arena);
    const journal = try g.Journal.init(&registry, std.enums.values(g.Color));

    const id = try registry.addNewEntity(g.entities.presets.Armor.get(.jacket));
    var text_area: g.windows.TextArea = .initEmpty(std.testing.allocator);
    defer text_area.deinit();

    // when:
    try describeItem(journal, id, false, &text_area);

    // then:
    try expectContent(text_area,
        \\A sturdy, time-worn leather jacket.
        \\Despite its worn  look, the  jacket
        \\offers     surprising    resilience
        \\against  scrapes   and  gives minor
        \\resistance to fire and heat.
        \\
        \\Protection: 0-5
    );
}

fn expectContent(actual: g.windows.TextArea, expectation: []const u8) !void {
    var i: usize = 0;
    errdefer {
        var buffer: [4096]u8 = undefined;
        var writer = std.Io.Writer.fixed(&buffer);
        actual.format(&writer) catch unreachable;
        std.debug.print("\n\nThe last compared line was {d}\n", .{i});
        std.debug.print("\nThe expectation is:\n--------------\n{s}\n--------------", .{expectation});
        std.debug.print("\n\nThe actual content was:\n--------------\n{s}\n--------------", .{buffer});
    }
    var itr = std.mem.splitScalar(u8, expectation, '\n');
    while (itr.next()) |line| {
        if (i >= actual.lines.items.len)
            return error.AbsentLineInActual;

        try std.testing.expectEqualStrings(line, std.mem.trimEnd(u8, &actual.lines.items[i], " \n"));
        i += 1;
    }
    if (i != actual.lines.items.len)
        return error.ActualLinesCountIsNotEqualToExpected;
}
