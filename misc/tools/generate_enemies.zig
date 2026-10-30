const std = @import("std");

const max_columns = 32;

const EnemyRow = struct {
    symbol: []const u8,
    name: []const u8,
    tier: []const u8,
    traits: []const u8,
    damage: []const u8,
    armor: []const u8,
    hp: []const u8,
    xp: []const u8,
};

pub fn generate(csv: []const u8, writer: *std.Io.Writer, diagnostic_writer: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, csv, '\n');
    const header = lines.next() orelse return error.EmptyCsv;
    var header_fields: [max_columns][]const u8 = undefined;
    const header_count = try splitRow(header, &header_fields);
    const name_col = findColumn(header_fields[0..header_count], "Name") orelse return error.MissingNameColumn;
    const tier_col = findColumn(header_fields[0..header_count], "Tier") orelse return error.MissingTierColumn;
    const symbol_col = findColumn(header_fields[0..header_count], "Symbol") orelse return error.MissingSymbolColumn;
    const trait_col = findColumn(header_fields[0..header_count], "Trait") orelse return error.MissingTraitColumn;
    const damage_col = findColumn(header_fields[0..header_count], "Damage") orelse return error.MissingDamageColumn;
    const armor_col = findColumn(header_fields[0..header_count], "Armor") orelse return error.MissingArmorColumn;
    const hp_col = findColumn(header_fields[0..header_count], "HP") orelse return error.MissingHPColumn;
    const xp_col = findColumn(header_fields[0..header_count], "XP") orelse return error.MissingXPColumn;

    var rows: std.ArrayList(EnemyRow) = .empty;
    defer rows.deinit(allocator);
    var traits: std.StringHashMap(void) = .init(allocator);
    defer traits.deinit();

    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0) continue;
        var fields: [max_columns][]const u8 = undefined;
        const count = try splitRow(line, &fields);
        const required = [_]usize{ symbol_col, name_col, tier_col, trait_col, damage_col, armor_col, hp_col, xp_col };
        if (count <= std.mem.max(usize, &required)) return error.MissingField;
        _ = std.fmt.parseInt(u4, std.mem.trim(u8, fields[tier_col], " \t"), 10) catch return error.InvalidTier;
        const row = EnemyRow{ .symbol = fields[symbol_col], .name = fields[name_col], .tier = fields[tier_col], .traits = fields[trait_col], .damage = fields[damage_col], .armor = fields[armor_col], .hp = fields[hp_col], .xp = fields[xp_col] };
        try rows.append(allocator, row);
        var iter = std.mem.splitScalar(u8, row.traits, ',');
        while (iter.next()) |raw_trait| {
            // A few cells combine tags with spaces (for example "ATK+ STATIC").
            var tags = std.mem.tokenizeScalar(u8, std.mem.trim(u8, raw_trait, " \t\r"), ' ');
            while (tags.next()) |tag| {
                if (std.mem.eql(u8, tag, "—")) continue;
                if (!isSupportedTrait(tag)) {
                    try diagnostic_writer.print(
                        "Unsupported enemy Trait '{s}'. Add support for this trait to the game code and to misc/tools/generate_enemies.zig.\n",
                        .{tag},
                    );
                    return error.UnsupportedTrait;
                }
                try traits.put(tag, {});
            }
        }
    }

    try writer.writeAll("const archetype = @import(\"archetypes.zig\");\nconst g = @import(\"../game_pkg.zig\");\nconst c = g.components;\n\n");
    try writer.writeAll("// Trait mapping reference (unique values from this CSV):\n");
    var trait_list: std.ArrayList([]const u8) = .empty;
    defer trait_list.deinit(allocator);
    var trait_iter = traits.iterator();
    while (trait_iter.next()) |entry| try trait_list.append(allocator, entry.key_ptr.*);
    std.mem.sort([]const u8, trait_list.items, {}, lessThan);
    for (trait_list.items) |trait| {
        try writer.writeAll("//   ");
        try writer.writeAll(trait);
        try writer.writeAll(" -> ");
        try writeTraitMapping(writer, trait);
        try writer.writeByte('\n');
    }

    try writer.writeByte('\n');
    for (rows.items) |row| {
        try writeSnakeCase(writer, row.name);
        try writer.writeAll(": c.Components = archetype.enemy(.{\n    .description = .{ .preset = .");
        try writeSnakeCase(writer, row.name);
        try writer.writeAll(" },\n    .tier = .{ .tier = ");
        try writer.writeAll(std.mem.trim(u8, row.tier, " \t"));
        try writer.writeAll(" },\n    .experience = .reward(");
        try writer.writeAll(std.mem.trim(u8, row.xp, " \t"));
        try writer.writeAll("),\n    .health = .init(");
        try writer.writeAll(std.mem.trim(u8, row.hp, " \t"));
        try writer.writeAll("),\n    .initiative = .empty,\n    .regeneration = .regular,\n    .skills = .zeros,\n");
        if (row.armor.len > 0) {
            try writer.writeAll("    .armor = .{ .protection = .range(");
            try writeArmor(writer, row.armor);
            try writer.writeAll(") },\n");
        }
        try writeImprovements(writer, row.traits);
        try writer.writeAll("    .speed = ");
        try writeSpeed(writer, row.traits);
        try writer.writeAll(",");
        try writer.writeAll("\n    .sprite = .{ .codepoint = '");
        try writer.writeAll(row.symbol);
        try writer.writeAll("' },\n    .state = .sleeping,\n    .stats = ");
        try writeStats(writer, row.traits);
        try writer.writeAll(",\n");
        if (std.mem.indexOf(u8, row.traits, "RNG(") != null) {
            const range_start = std.mem.indexOf(u8, row.traits, "RNG(").? + 4;
            const range_end = std.mem.indexOfPos(u8, row.traits, range_start, ")") orelse return error.InvalidRange;
            const distance = row.traits[range_start..range_end];
            try writer.writeAll("    .weapon = .ranged(.native, .range(");
            try writeDamage(writer, row.damage);
            try writer.writeAll("), ");
            try writer.writeAll(distance);
            try writer.writeAll(", .bullets),\n}),\n\n");
        } else {
            try writer.writeAll("    .weapon = ");
            try writeWeapon(writer, row.damage, row.traits);
            try writer.writeAll("\n}),\n\n");
        }
    }
}

fn isSupportedTrait(trait: []const u8) bool {
    const known = [_][]const u8{
        "SPD+", "SPD-", "ATK+", "ATK-", "STR+", "STR-", "DEX+",   "DEX-",
        "PER+", "PER-", "INT+", "INT-", "FIRE", "ACID", "POISON", "F+",
        "F-",   "A+",   "A-",   "P+",   "P-",   "ARM",  "STATIC",
    };
    for (known) |item| if (std.mem.eql(u8, trait, item)) return true;

    if (std.mem.startsWith(u8, trait, "RNG(") and std.mem.endsWith(u8, trait, ")")) {
        const distance = trait[4 .. trait.len - 1];
        if (distance.len == 0) return false;
        _ = std.fmt.parseInt(u8, distance, 10) catch return false;
        return true;
    }
    return false;
}

fn writeTraitMapping(writer: *std.Io.Writer, trait: []const u8) !void {
    if (std.mem.eql(u8, trait, "SPD+")) return writer.writeAll("speed = .@\"spd+\"");
    if (std.mem.eql(u8, trait, "ATK+")) return writer.writeAll("speed = .@\"atk+\"");
    if (std.mem.eql(u8, trait, "F-")) return writer.writeAll("breakages = .@\"fire-\"");
    if (std.mem.eql(u8, trait, "POISON") or std.mem.eql(u8, trait, "FIRE") or std.mem.eql(u8, trait, "ACID")) return writer.writeAll("weapon effect via meleeWithEffect/rangedWithEffect(..., .poison/.fire/.acid)");
    if (std.mem.eql(u8, trait, "ARM")) return writer.writeAll("armor.protection uses the numeric Armor column");
    if (std.mem.eql(u8, trait, "DEX+") or std.mem.eql(u8, trait, "DEX-") or std.mem.eql(u8, trait, "PER+") or std.mem.eql(u8, trait, "PER-") or std.mem.eql(u8, trait, "STR+") or std.mem.eql(u8, trait, "STR-") or std.mem.eql(u8, trait, "INT+") or std.mem.eql(u8, trait, "INT-")) {
        const stat = if (std.mem.indexOf(u8, trait, "STR") != null) "strength" else if (std.mem.indexOf(u8, trait, "DEX") != null) "dexterity" else if (std.mem.indexOf(u8, trait, "PER") != null) "perception" else "intelligence";
        const sign: i8 = if (trait[trait.len - 1] == '+')
            (if (std.mem.startsWith(u8, trait, "PER")) 2 else 1)
        else if (std.mem.startsWith(u8, trait, "PER"))
            -2
        else
            -1;
        try writer.print("stats = .init({s} {d}, ...)", .{ stat, sign });
        return;
    }
    if (std.mem.startsWith(u8, trait, "RNG(")) return writer.writeAll("weapon = .ranged(..., max_distance, .bullets)");
    if (std.mem.eql(u8, trait, "F+") or std.mem.eql(u8, trait, "A+") or std.mem.eql(u8, trait, "P+")) {
        const effect = if (trait[0] == 'F') "fire" else if (trait[0] == 'A') "acid" else "poison";
        return writer.print(".improvements = .{{ .modifications = .init(&.{{ .{s} }}) }}", .{effect});
    }
    if (std.mem.eql(u8, trait, "F-") or std.mem.eql(u8, trait, "A-") or std.mem.eql(u8, trait, "P-")) {
        const effect = if (trait[0] == 'F') "fire" else if (trait[0] == 'A') "acid" else "poison";
        return writer.print(".breakages = .{{ .modifications = .init(&.{{ .{s} }}) }}", .{effect});
    }
    if (std.mem.eql(u8, trait, "STATIC")) return writer.writeAll("speed = .@\"static; atk+\" when combined with ATK+");
    if (std.mem.eql(u8, trait, "SPD-")) return writer.writeAll("speed = .@\"spd-\" (or .@\"spd-; atk-\" with ATK-)");
    if (std.mem.eql(u8, trait, "ATK-")) return writer.writeAll("speed = .@\"atk-\" (or .@\"spd-; atk-\" with SPD-)");
    return error.UnsupportedTrait;
}

fn writeSpeed(writer: *std.Io.Writer, trait_list: []const u8) !void {
    const static = hasTrait(trait_list, "STATIC");
    const spd_up = std.mem.indexOf(u8, trait_list, "SPD+") != null;
    const atk_up = std.mem.indexOf(u8, trait_list, "ATK+") != null;
    const spd_down = hasTrait(trait_list, "SPD-");
    const atk_down = hasTrait(trait_list, "ATK-");
    if (static and atk_up) return writer.writeAll(".@\"static; atk+\"");
    if (spd_down and atk_down) return writer.writeAll(".@\"spd-; atk-\"");
    if (spd_down) return writer.writeAll(".@\"spd-\"");
    if (atk_down) return writer.writeAll(".@\"atk-\"");
    if (spd_up and atk_up) return writer.writeAll(".@\"spd+; atk+\"");
    if (spd_up) return writer.writeAll(".@\"spd+\"");
    if (atk_up) return writer.writeAll(".@\"atk+\"");
    return writer.writeAll(".default");
}

fn writeStats(writer: *std.Io.Writer, trait_list: []const u8) !void {
    const strength: i8 = if (hasTrait(trait_list, "STR+")) 1 else if (hasTrait(trait_list, "STR-")) -1 else 0;
    const dexterity: i8 = if (hasTrait(trait_list, "DEX+")) 1 else if (hasTrait(trait_list, "DEX-")) -1 else 0;
    const perception: i8 = if (hasTrait(trait_list, "PER+")) 2 else if (hasTrait(trait_list, "PER-")) -2 else 0;
    const intelligence: i8 = if (hasTrait(trait_list, "INT+")) 1 else if (hasTrait(trait_list, "INT-")) -1 else 0;
    return writer.print(".init({d}, {d}, {d}, {d}, 0)", .{ strength, dexterity, perception, intelligence });
}

fn writeWeapon(writer: *std.Io.Writer, damage: []const u8, trait_list: []const u8) !void {
    const effect: ?[]const u8 = if (hasTrait(trait_list, "FIRE")) "fire" else if (hasTrait(trait_list, "ACID")) "acid" else if (hasTrait(trait_list, "POISON")) "poison" else null;
    try writer.writeAll(".melee");
    if (effect) |name| {
        try writer.writeAll("WithEffect(.native, .range(");
        try writeDamage(writer, damage);
        try writer.writeAll("), .");
        try writer.writeAll(name);
        return writer.writeAll("),");
    }
    try writer.writeAll("(.native, .range(");
    try writeDamage(writer, damage);
    try writer.writeAll(")),");
}

fn hasTrait(traits: []const u8, tag: []const u8) bool {
    var iter = std.mem.tokenizeAny(u8, traits, ", \t");
    while (iter.next()) |part| if (std.mem.eql(u8, part, tag)) return true;
    return false;
}

fn writeImprovements(writer: *std.Io.Writer, traits: []const u8) !void {
    const tags = [_][]const u8{ "F+", "A+", "P+" };
    const effects = [_][]const u8{ "fire", "acid", "poison" };
    var found = false;
    for (tags) |tag| if (hasTrait(traits, tag)) {
        found = true;
        break;
    };
    if (!found) return;

    try writer.writeAll("    .improvements = .{ .modifications = .init(&.{ ");
    var first = true;
    for (tags, effects) |tag, effect| {
        if (!hasTrait(traits, tag)) continue;
        if (!first) try writer.writeAll(", ");
        first = false;
        try writer.writeAll(".");
        try writer.writeAll(effect);
    }
    try writer.writeAll(" }) },\n");
}

fn writeArmor(writer: *std.Io.Writer, value: []const u8) !void {
    const protection = std.fmt.parseInt(u8, std.mem.trim(u8, value, " \t"), 10) catch return error.InvalidArmor;
    try writer.print("{d}, {d}", .{ protection, protection });
}

fn writeDamage(writer: *std.Io.Writer, value: []const u8) !void {
    const dash = std.mem.indexOfScalar(u8, value, '-') orelse std.mem.indexOf(u8, value, "–") orelse return error.InvalidDamage;
    const sep_len: usize = if (value[dash] == '-') 1 else "–".len;
    const min = std.mem.trim(u8, value[0..dash], " \t");
    const max = std.mem.trim(u8, value[dash + sep_len ..], " \t");
    _ = std.fmt.parseInt(u8, min, 10) catch return error.InvalidRange;
    _ = std.fmt.parseInt(u8, max, 10) catch return error.InvalidRange;
    try writer.writeAll(min);
    try writer.writeAll(", ");
    try writer.writeAll(max);
}

fn findColumn(columns: []const []const u8, name: []const u8) ?usize {
    for (columns, 0..) |column, index| if (std.mem.eql(u8, std.mem.trim(u8, column, " \r"), name)) return index;
    return null;
}
fn lessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
fn splitRow(row: []const u8, fields: *[max_columns][]const u8) !usize {
    var iter = std.mem.splitScalar(u8, row, ';');
    var count: usize = 0;
    while (iter.next()) |field| {
        if (count == fields.len) return error.TooManyColumns;
        fields[count] = field;
        count += 1;
    }
    return count;
}
fn writeSnakeCase(writer: *std.Io.Writer, value: []const u8) !void {
    var content = false;
    var sep = false;
    var i: usize = 0;
    while (i < value.len) : (i += 1) {
        const ch = value[i];
        if ((ch >= 'a' and ch <= 'z') or (ch >= '0' and ch <= '9') or (ch >= 'A' and ch <= 'Z')) {
            if (sep and content) try writer.writeByte('_');
            try writer.writeByte(if (ch >= 'A' and ch <= 'Z') ch + ('a' - 'A') else ch);
            content = true;
            sep = false;
        } else if (content) sep = true;
    }
}
