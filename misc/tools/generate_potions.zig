const std = @import("std");

const max_csv_size = 1024 * 1024;
const max_columns = 32;

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

    try generate(csv, &stdout.interface);
    try stdout.interface.flush();
}

fn generate(csv: []const u8, writer: *std.Io.Writer) !void {
    var lines = std.mem.splitScalar(u8, csv, '\n');
    const header = lines.next() orelse return error.EmptyCsv;

    var header_fields: [max_columns][]const u8 = undefined;
    const header_count = splitRow(header, &header_fields) catch return error.TooManyColumns;
    const name_column = findColumn(header_fields[0..header_count], "Name") orelse
        return error.MissingNameColumn;
    const price_column = findColumn(header_fields[0..header_count], "Price (known)") orelse
        return error.MissingKnownPriceColumn;

    try writer.writeAll(
        "const archetype = @import(\"archetypes.zig\");\n" ++
            "const cp = @import(\"../codepoints.zig\");\n" ++
            "const g = @import(\"../game_pkg.zig\");\n" ++
            "const c = g.components;\n\n",
    );

    var first = true;
    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0)
            continue;

        var fields: [max_columns][]const u8 = undefined;
        const field_count = splitRow(line, &fields) catch return error.TooManyColumns;
        if (field_count <= @max(name_column, price_column))
            return error.MissingField;

        const name = fields[name_column];
        const price = fields[price_column];
        _ = std.fmt.parseInt(u16, price, 10) catch return error.InvalidPrice;

        if (!first)
            try writer.writeAll("\n");
        first = false;

        try writeSnakeCase(writer, name);
        try writer.writeAll("_potion: c.Components = archetype.potion(.{\n");
        try writer.writeAll("    .description = .{ .preset = .");
        try writeSnakeCase(writer, name);
        try writer.writeAll("_potion },\n    .sprite = .{ .codepoint = cp.potion },\n    .price = .{ .value = ");
        try writer.writeAll(price);
        try writer.writeAll(" },\n    .potion = .");
        try writeSnakeCase(writer, name);
        try writer.writeAll(",\n}),\n");
    }
}

fn findColumn(columns: []const []const u8, name: []const u8) ?usize {
    for (columns, 0..) |column, index| {
        if (std.mem.eql(u8, std.mem.trim(u8, column, " \r"), name))
            return index;
    }
    return null;
}

fn splitRow(row: []const u8, fields: *[max_columns][]const u8) !usize {
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
