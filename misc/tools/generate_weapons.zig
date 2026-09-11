const std = @import("std");

const max_csv_size = 1024 * 1024;
const max_columns = 32;

const Damage = struct {
    min: u8,
    max: u8,
};

const WeaponRow = struct {
    name: []const u8,
    damage: Damage,
    stat: []const u8,
    range: u8,
    ammo: ?[]const u8,
    effect: ?[]const u8,
    price: u16,
};

const Stat = enum { STR, DEX, INT };
const Ammo = enum { Arrows, Bolts, Bullets };
const Effect = enum { Fire, Poison, Acid };

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.next();
    const csv_path = args.next() orelse return error.MissingCsvPath;

    const csv = try std.Io.Dir.cwd().readFileAlloc(
        init.io,
        csv_path,
        init.gpa,
        .limited(max_csv_size),
    );
    defer init.gpa.free(csv);

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    defer stdout.interface.flush() catch {};

    try generate(csv, &stdout.interface, init.gpa);
    try stdout.interface.flush();
}

fn generate(csv: []const u8, writer: *std.Io.Writer, allocator: std.mem.Allocator) !void {
    var lines = std.mem.splitScalar(u8, csv, '\n');
    const header = lines.next() orelse return error.EmptyCsv;

    var header_fields: [max_columns][]const u8 = undefined;
    const header_count = splitRow(header, &header_fields) catch return error.TooManyColumns;
    const name_column = findColumn(header_fields[0..header_count], "Name") orelse
        return error.MissingNameColumn;
    const damage_column = findColumn(header_fields[0..header_count], "Damage") orelse
        return error.MissingDamageColumn;
    const stat_column = findColumn(header_fields[0..header_count], "Stat") orelse
        return error.MissingStatColumn;
    const range_column = findColumn(header_fields[0..header_count], "Range") orelse
        return error.MissingRangeColumn;
    const ammo_column = findColumn(header_fields[0..header_count], "Ammo") orelse
        return error.MissingAmmoColumn;
    const effect_column = findColumn(header_fields[0..header_count], "Effect") orelse
        return error.MissingEffectColumn;
    const price_column = findColumn(header_fields[0..header_count], "Price") orelse
        return error.MissingPriceColumn;

    var rows: std.ArrayList(WeaponRow) = .empty;
    defer rows.deinit(allocator);

    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0)
            continue;

        const columns = [_]usize{
            name_column,
            damage_column,
            stat_column,
            range_column,
            ammo_column,
            effect_column,
            price_column,
        };
        var fields: [max_columns][]const u8 = undefined;
        const field_count = splitRow(line, &fields) catch return error.TooManyColumns;
        if (field_count <= std.mem.max(usize, &columns))
            return error.MissingField;

        const price = std.fmt.parseInt(u16, fields[price_column], 10) catch return error.InvalidPrice;
        const range = std.fmt.parseInt(u8, fields[range_column], 10) catch return error.InvalidRange;
        try rows.append(allocator, .{
            .name = fields[name_column],
            .damage = try parseDamage(fields[damage_column]),
            .stat = fields[stat_column],
            .range = range,
            .ammo = if (fields[ammo_column].len == 0) null else fields[ammo_column],
            .effect = if (fields[effect_column].len == 0) null else fields[effect_column],
            .price = price,
        });
    }

    std.mem.sort(WeaponRow, rows.items, {}, lessThanByName);

    try writer.writeAll(
        "const archetype = @import(\"archetypes.zig\");\n" ++
            "const cp = @import(\"../codepoints.zig\");\n" ++
            "const g = @import(\"../game_pkg.zig\");\n" ++
            "const c = g.components;\n\n",
    );

    var first = true;
    for (rows.items) |row| {
        if (!first)
            try writer.writeAll("\n");
        first = false;

        try writeSnakeCase(writer, row.name);
        try writer.writeAll(": c.Components = archetype.weapon(.{\n");
        try writer.writeAll("    .description = .{ .preset = .");
        try writeSnakeCase(writer, row.name);
        try writer.writeAll(" },\n    .sprite = .{ .codepoint = ");
        try writer.writeAll(if (row.ammo != null) "cp.weapon_ranged" else "cp.weapon_melee");
        try writer.writeAll(" },\n    .price = .{ .value = ");
        try writer.print("{d}", .{row.price});
        try writer.writeAll(" },\n");
        try writer.writeAll("    .weapon = ");
        try writeWeapon(writer, row);
        try writer.writeAll(",\n}),\n");
    }
}

fn parseDamage(value: []const u8) !Damage {
    const separator = std.mem.indexOfScalar(u8, value, '-') orelse
        return error.InvalidDamage;
    const min = std.fmt.parseInt(u8, value[0..separator], 10) catch return error.InvalidDamage;
    const max = std.fmt.parseInt(u8, value[separator + 1 ..], 10) catch return error.InvalidDamage;
    if (min > max)
        return error.InvalidDamage;
    return .{ .min = min, .max = max };
}

fn writeWeapon(writer: *std.Io.Writer, row: WeaponRow) !void {
    if (row.ammo) |ammo| {
        if (row.effect) |effect| {
            try writer.print(
                ".rangedWithEffect({s}, .range({d}, {d}), {d}, {s}, {s})",
                .{ try weaponClass(row.stat), row.damage.min, row.damage.max, row.range, try ammoTag(ammo), try effectTag(effect) },
            );
        } else {
            try writer.print(
                ".ranged({s}, .range({d}, {d}), {d}, {s})",
                .{ try weaponClass(row.stat), row.damage.min, row.damage.max, row.range, try ammoTag(ammo) },
            );
        }
    } else if (row.effect) |effect| {
        try writer.print(
            ".meleeWithEffect({s}, .range({d}, {d}), {s})",
            .{ try weaponClass(row.stat), row.damage.min, row.damage.max, try effectTag(effect) },
        );
    } else {
        try writer.print(
            ".melee({s}, .range({d}, {d}))",
            .{ try weaponClass(row.stat), row.damage.min, row.damage.max },
        );
    }
}

fn weaponClass(stat: []const u8) ![]const u8 {
    const stat_tag = std.meta.stringToEnum(Stat, stat) orelse return error.WrongStatValue;
    return switch (stat_tag) {
        .STR => ".primitive",
        .DEX => ".tricky",
        .INT => ".ancient",
    };
}

fn ammoTag(ammo: []const u8) ![]const u8 {
    const ammo_tag = std.meta.stringToEnum(Ammo, ammo) orelse return error.WrongAmmoValue;
    return switch (ammo_tag) {
        .Arrows => ".arrows",
        .Bolts => ".bolts",
        .Bullets => ".bullets",
    };
}

fn effectTag(effect: []const u8) ![]const u8 {
    const effect_tag = std.meta.stringToEnum(Effect, effect) orelse return error.WrongEffectValue;
    return switch (effect_tag) {
        .Fire => ".fire",
        .Poison => ".poison",
        .Acid => ".acid",
    };
}

fn lessThanByName(_: void, lhs: WeaponRow, rhs: WeaponRow) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
}

fn findColumn(columns: []const []const u8, name: []const u8) ?usize {
    for (columns, 0..) |column, index| {
        if (std.mem.eql(u8, std.mem.trim(u8, column, " \r"), name))
            return index;
    }
    return null;
}

fn splitRow(row: []const u8, fields: [][]const u8) !usize {
    var columns = std.mem.splitScalar(u8, row, ';');
    var count: usize = 0;
    while (columns.next()) |column| {
        if (count == fields.len)
            return error.TooManyColumns;
        fields[count] = column;
        count += 1;
    }
    return count;
}

fn writeSnakeCase(writer: *std.Io.Writer, value: []const u8) !void {
    var has_content = false;
    var separator_pending = false;
    var index: usize = 0;
    while (index < value.len) {
        if (index + 2 < value.len and value[index] == 0xe2 and value[index + 1] == 0x80 and value[index + 2] == 0x99) {
            index += 3;
            if (has_content)
                separator_pending = true;
            continue;
        }

        const char = value[index];
        if ((char >= 'a' and char <= 'z') or (char >= '0' and char <= '9')) {
            if (separator_pending and has_content)
                try writer.writeByte('_');
            try writer.writeByte(char);
            has_content = true;
            separator_pending = false;
        } else if (char >= 'A' and char <= 'Z') {
            if (separator_pending and has_content)
                try writer.writeByte('_');
            try writer.writeByte(char + ('a' - 'A'));
            has_content = true;
            separator_pending = false;
        } else if (has_content) {
            separator_pending = true;
        }
        index += 1;
    }
}
