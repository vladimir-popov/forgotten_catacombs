const std = @import("std");
const g = @import("game");

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

pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
    var buf: [4]u8 = undefined;
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            const sprite = self.sprites[r][c];
            if (sprite.codepoint == 0) {
                _ = try writer.writeByte(' ');
            } else if (sprite.codepoint <= 127) {
                try writer.writeByte(@truncate(sprite.codepoint));
            } else {
                const len = try std.unicode.utf8Encode(sprite.codepoint, &buf);
                _ = try writer.write(buf[0..len]);
            }
        }
        try writer.writeByte('\n');
    }
}

pub fn toTtyFromat(self: Self) TtyFormat {
    return .{ .frame = self };
}

pub const TtyFormat = struct {
    const tty = @import("terminal").tty;

    frame: Self,

    pub fn format(self: TtyFormat, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var buf: [4]u8 = undefined;
        for (0..g.DISPLAY_ROWS) |r| {
            var mode: g.DrawingMode = .normal;
            for (0..g.DISPLAY_COLS) |c| {
                const sprite = self.frame.sprites[r][c];
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
                    const len = try std.unicode.utf8Encode(sprite.codepoint, &buf);
                    _ = try writer.write(buf[0..len]);
                }
            }
            _ = try writer.write(tty.Text.SGR_RESET);
            try writer.writeByte('\n');
        }
    }
};

pub fn expectEqual(self: Self, other: Self) !void {
    var has_difference = false;
    var diff: Self = .empty;
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            const expected = self.sprites[r][c];
            const actual = other.sprites[r][c];
            if (!std.meta.eql(expected, actual)) {
                diff.sprites[r][c] = actual;
                has_difference = true;
            }
        }
    }
    if (has_difference) {
        std.debug.print("\nExpected frame:\n{any}", .{self.toTtyFromat()});
        std.debug.print("\nActual frame:\n{any}", .{other.toTtyFromat()});
        std.debug.print("\nDifference:\n{any}", .{diff.toTtyFromat()});
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
            r += 1;
            c = 0;
            continue;
        }
        const codepoint = self.sprites[r][c].codepoint;
        if (symbol == ' ' and codepoint == 0) {
            c += 1;
            continue;
        }
        if (codepoint != symbol) {
            diff.sprites[r][c].codepoint = symbol;
            has_difference = true;
        }
        c += 1;
    }
    if (has_difference) {
        std.debug.print("\nExpected:\n{s}", .{str});
        std.debug.print("\nActual frame:\n{any}", .{self.toTtyFromat()});
        std.debug.print("\nDifference:\n{any}", .{diff});
        return error.TestExpectedEqual;
    }
}
