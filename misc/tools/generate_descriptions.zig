const std = @import("std");

const max_csv_size = 1024 * 1024;
const max_columns = 32;
const max_line_length = 35;
const max_words = 64;

const DescriptionRow = struct {
    name: []const u8,
    description: []const u8,
};

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
    const description_column = findColumn(header_fields[0..header_count], "Description") orelse
        return error.MissingDescriptionColumn;

    var rows: std.ArrayList(DescriptionRow) = .empty;
    defer rows.deinit(allocator);

    while (lines.next()) |raw_line| {
        const line = std.mem.trimEnd(u8, raw_line, "\r");
        if (line.len == 0)
            continue;

        var fields: [max_columns][]const u8 = undefined;
        const field_count = splitRow(line, &fields) catch return error.TooManyColumns;
        if (field_count <= @max(name_column, description_column))
            return error.MissingField;

        try rows.append(allocator, .{
            .name = fields[name_column],
            .description = fields[description_column],
        });
    }

    std.mem.sort(DescriptionRow, rows.items, {}, lessThanByName);

    for (rows.items) |row| {
        const name = row.name;
        const description = row.description;

        try writeSnakeCase(writer, name);
        try writer.writeAll(": g.Description = .{\n    .name = \"");
        try writeEscaped(writer, name);
        try writer.writeAll("\",\n    .description = &.{\n");
        try writeWrappedDescription(writer, description);
        try writer.writeAll("    },\n},\n\n");
    }
}

fn lessThanByName(_: void, lhs: DescriptionRow, rhs: DescriptionRow) bool {
    return std.mem.lessThan(u8, lhs.name, rhs.name);
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

fn writeWrappedDescription(writer: *std.Io.Writer, description: []const u8) !void {
    var words: [max_words][]const u8 = undefined;
    var word_count: usize = 0;
    var word_start: ?usize = null;

    for (description, 0..) |char, index| {
        if (char == ' ') {
            if (word_start) |start| {
                if (word_count == words.len)
                    return error.TooManyWords;
                words[word_count] = description[start..index];
                word_count += 1;
                word_start = null;
            }
        } else if (word_start == null) {
            word_start = index;
        }
    }
    if (word_start) |start| {
        if (word_count == words.len)
            return error.TooManyWords;
        words[word_count] = description[start..];
        word_count += 1;
    }

    var first_word: usize = 0;
    while (first_word < word_count) {
        var last_word = first_word + 1;
        var words_length = words[first_word].len;
        while (last_word < word_count and
            words_length + 1 + words[last_word].len <= max_line_length)
        {
            words_length += 1 + words[last_word].len;
            last_word += 1;
        }

        try writeJustifiedLine(
            writer,
            words[first_word..last_word],
            words_length,
            last_word == word_count,
        );
        first_word = last_word;
    }
}

fn writeJustifiedLine(
    writer: *std.Io.Writer,
    words: []const []const u8,
    words_length: usize,
    is_last_line: bool,
) !void {
    const gaps = words.len -| 1;
    const extra_spaces = if (is_last_line) gaps else max_line_length - words_length + gaps;
    const spaces_per_gap = if (gaps == 0) 0 else extra_spaces / gaps;
    const gaps_with_extra_space = if (gaps == 0) 0 else extra_spaces % gaps;

    try writer.writeAll("        \"");
    for (words, 0..) |word, index| {
        try writeEscaped(writer, word);
        if (index + 1 < words.len) {
            const gap = spaces_per_gap +
                @intFromBool(!is_last_line and index < gaps_with_extra_space);
            _ = try writer.splatByte(' ', gap);
        }
    }
    try writer.writeAll("\",\n");
}

fn writeEscaped(writer: *std.Io.Writer, value: []const u8) !void {
    for (value) |char| {
        switch (char) {
            '\\' => try writer.writeAll("\\\\"),
            '"' => try writer.writeAll("\\\""),
            else => try writer.writeByte(char),
        }
    }
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
