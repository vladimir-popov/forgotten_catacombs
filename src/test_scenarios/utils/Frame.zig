const std = @import("std");
const g = @import("game");
const tty = @import("terminal").tty;
const WriterError = std.Io.Writer.Error;

const log = std.log.scoped(.test_utils);

const Self = @This();

sprites: [g.DISPLAY_ROWS][g.DISPLAY_COLS]g.Render.DrawableSymbol,

pub const empty: Self = blk: {
    var frame: Self = undefined;
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            frame.sprites[r][c].codepoint = 0;
            frame.sprites[r][c].mode = .normal;
        }
    }
    break :blk frame;
};

pub fn merge(self: *Self, other: Self) void {
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            if (other.sprites[r][c].codepoint > 0)
                self.sprites[r][c] = other.sprites[r][c];
        }
    }
}

pub fn format(self: @This(), writer: *std.Io.Writer) WriterError!void {
    for (0..g.DISPLAY_ROWS) |r| {
        try self.formatRow(writer, r);
        try writer.writeByte('\n');
    }
}

pub fn formatRow(self: @This(), writer: *std.Io.Writer, row_idx: usize) WriterError!void {
    var buf: [4]u8 = undefined;
    for (0..g.DISPLAY_COLS) |c| {
        const sprite = self.sprites[row_idx][c];
        if (sprite.codepoint == 0) {
            _ = try writer.writeByte(' ');
        } else if (sprite.codepoint <= 127) {
            try writer.writeByte(@truncate(sprite.codepoint));
        } else {
            const len = std.unicode.utf8Encode(sprite.codepoint, &buf) catch |err| {
                log.err("Error {t} on encoding utf8 {any}", .{ err, sprite.codepoint });
                return error.WriteFailed;
            };
            _ = try writer.write(buf[0..len]);
        }
    }
}

pub fn ttyFormat(self: @This(), writer: *std.Io.Writer) WriterError!void {
    var buf: [4]u8 = undefined;
    for (0..g.DISPLAY_ROWS) |r| {
        var mode: g.DrawingMode = .normal;
        for (0..g.DISPLAY_COLS) |c| {
            const sprite = self.sprites[r][c];
            if (mode != sprite.mode) {
                mode = sprite.mode;
                switch (mode) {
                    .inverted => _ = try writer.write(tty.Text.SGR_INVERT_COLORS),
                    else => _ = try writer.write(tty.Text.SGR_RESET),
                }
            }
            if (sprite.codepoint == 0) {
                _ = try writer.write("�");
            } else if (sprite.codepoint <= 127) {
                try writer.writeByte(@truncate(sprite.codepoint));
            } else {
                const len = std.unicode.utf8Encode(sprite.codepoint, &buf) catch |err| {
                    log.err("Error {t} on encoding utf8 {any}", .{ err, sprite.codepoint });
                    return error.WriteFailed;
                };
                _ = try writer.write(buf[0..len]);
            }
        }
        _ = try writer.write(tty.Text.SGR_RESET);
        try writer.writeByte('\n');
    }
}

pub fn expectEqual(self: Self, expected: Self) !void {
    var has_difference = false;
    var diff: Self = .empty;
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            const exp = expected.sprites[r][c];
            const act = self.sprites[r][c];
            if (!std.meta.eql(exp, act)) {
                diff.sprites[r][c] = act;
                has_difference = true;
            }
        }
    }
    if (has_difference) {
        std.debug.print("\nExpected frame:\n{f}", .{std.fmt.alt(expected, .ttyFormat)});
        std.debug.print("\nActual frame:\n{f}", .{std.fmt.alt(self, .ttyFormat)});
        std.debug.print("\nDifference:\n{f}", .{std.fmt.alt(diff, .ttyFormat)});
        return error.TestExpectedEqual;
    }
}

pub fn expectLooksLike(self: Self, str: []const u8) !void {
    var has_difference = false;
    var diff: Self = .empty;
    const symbols = try std.unicode.Utf8View.init(str);
    var itr = symbols.iterator();
    var r: usize = 0;
    var c: usize = 0;
    while (itr.nextCodepoint()) |symbol| {
        if (symbol == '\n') {
            if (c < self.sprites[r].len) {
                for (c..self.sprites[r].len) |c0| {
                    const codepoint = self.sprites[r][c0].codepoint;
                    if (codepoint > 0 and codepoint != ' ') {
                        diff.sprites[r][c0].codepoint = if (codepoint == ' ') '¶' else codepoint;
                        has_difference = true;
                    }
                }
            }
            r += 1;
            c = 0;
            continue;
        }
        const codepoint = self.sprites[r][c].codepoint;
        if (!isEqual(codepoint, symbol)) {
            diff.sprites[r][c].codepoint = if (codepoint == ' ') '¶' else codepoint;
            has_difference = true;
        }
        c += 1;
    }
    if (has_difference) {
        std.debug.print("\nExpected (highlighting omitted):\n{s}", .{str});
        std.debug.print("\nActual frame:\n{f}", .{std.fmt.alt(self, .ttyFormat)});
        std.debug.print("\nDifference (from actual frame):\n{f}", .{diff});
        return error.TestExpectedEqual;
    }
}
fn isEqual(codepoint: u21, expected_symbol: u21) bool {
    // special cases for blank symbol
    if (codepoint == 0) {
        return isBlank(expected_symbol);
    }
    return codepoint == expected_symbol;
}

fn isBlank(codepoint: u21) bool {
    return switch (codepoint) {
        0, ' ', '�' => true,
        else => false,
    };
}

pub fn expectRowLooksLike(self: Self, row_idx: usize, expected_row: []const u8) !void {
    var has_difference = false;
    var diff: Self = .empty;
    const symbols = try std.unicode.Utf8View.init(expected_row);
    var itr = symbols.iterator();
    var c: usize = 0;
    while (itr.nextCodepoint()) |symbol| {
        if (symbol == '\n') {
            if (c < self.sprites[row_idx].len) {
                for (c..self.sprites[row_idx].len) |c0| {
                    const codepoint = self.sprites[row_idx][c0].codepoint;
                    if (codepoint > 0 and codepoint != ' ') {
                        diff.sprites[row_idx][c0].codepoint = if (codepoint == ' ') '¶' else codepoint;
                        has_difference = true;
                    }
                }
            }
            std.debug.assert(itr.nextCodepoint() == null);
            break;
        }
        const codepoint = self.sprites[row_idx][c].codepoint;
        if (symbol == ' ' and codepoint == 0) {
            c += 1;
            continue;
        }
        if (codepoint != symbol) {
            diff.sprites[row_idx][c].codepoint = if (codepoint == ' ') '¶' else codepoint;
            has_difference = true;
        }
        c += 1;
    }
    if (has_difference) {
        std.debug.print("\nExpected row (highlighting omitted):\n{s}", .{expected_row});
        var buffer: [64]u8 = undefined;
        const bw = std.debug.lockStderrWriter(&buffer);
        defer std.debug.unlockStderrWriter();
        try bw.writeAll("\nActual row:\n");
        try self.formatRow(bw, row_idx);
        try bw.writeAll("\nDifference (from actual frame):\n");
        try diff.formatRow(bw, row_idx);
        try bw.writeByte('\n');
        return error.TestExpectedEqual;
    }
}
