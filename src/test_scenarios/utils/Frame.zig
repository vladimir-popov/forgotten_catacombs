const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("terminal").tty;
const WriterError = std.Io.Writer.Error;

const log = std.log.scoped(.test_utils);

const Self = @This();

const zero_symbol = '�';
const space_symbol = '¶';

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

pub const ComparingArea = union(enum) {
    whole_display,
    game_area,
    region: p.Region,
    line: u8,
    fn toRegion(self: ComparingArea) p.Region {
        return switch (self) {
            .whole_display => p.Region.init(1, 1, g.DISPLAY_ROWS, g.DISPLAY_COLS),
            .game_area => p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS),
            .region => |reg| reg,
            .line => |l| p.Region.init(l, 1, 1, g.DISPLAY_COLS),
        };
    }
};

/// Used to format a region of the frame.
const FormatedArea = struct {
    const OutputOptions = struct {
        tty_output: bool = false,
        zero_symbol: u21 = zero_symbol,
        space_symbol: u21 = space_symbol,

        const flat = OutputOptions{ .tty_output = false, .zero_symbol = zero_symbol, .space_symbol = ' ' };
        const actual = OutputOptions{ .tty_output = true, .zero_symbol = zero_symbol, .space_symbol = ' ' };
        const diff = OutputOptions{ .tty_output = true, .zero_symbol = ' ', .space_symbol = space_symbol };
    };

    frame: *const Self,
    area: ComparingArea,
    opt: OutputOptions = .{},

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        var mode: g.DrawingMode = .normal;
        const region = self.area.toRegion();
        var itr = region.cells();
        while (itr.next()) |cell| {
            const sprite = self.frame.sprites[cell.row - 1][cell.col - 1];
            if (self.opt.tty_output and mode != sprite.mode) {
                mode = sprite.mode;
                switch (mode) {
                    .inverted => _ = try writer.write(tty.Text.SGR_INVERT_COLORS),
                    else => _ = try writer.write(tty.Text.SGR_RESET),
                }
            }
            const codepoint = if (sprite.codepoint == ' ')
                self.opt.space_symbol
            else if (sprite.codepoint == 0)
                self.opt.zero_symbol
            else
                sprite.codepoint;
            try writer.print("{u}", .{codepoint});
            if (cell.col - region.top_left.col == region.cols - 1) {
                if (self.opt.tty_output) {
                    _ = try writer.write(tty.Text.SGR_RESET);
                }
                try writer.writeByte('\n');
            }
        }
    }
};

fn formatArea(self: *const Self, area: ComparingArea, opt: FormatedArea.OutputOptions) FormatedArea {
    return .{ .frame = self, .area = area, .opt = opt };
}

pub fn merge(self: *Self, other: Self) void {
    for (0..g.DISPLAY_ROWS) |r| {
        for (0..g.DISPLAY_COLS) |c| {
            if (other.sprites[r][c].codepoint > 0)
                self.sprites[r][c] = other.sprites[r][c];
        }
    }
}

pub fn format(self: @This(), writer: *std.Io.Writer) WriterError!void {
    try self.formatArea(.whole_display, .flat).format(writer);
}

pub fn ttyFormat(self: @This(), writer: *std.Io.Writer) WriterError!void {
    try self.formatArea(.whole_display, .actual).format(writer);
}

pub fn expectLooksLike(self: Self, expectation: []const u8, area: ComparingArea) !void {
    if (try self.diffInArea(try parse(expectation, area.toRegion()), area)) |diff| {
        var buffer: [g.DISPLAY_ROWS * g.DISPLAY_COLS * 4]u8 = @splat(0);
        _ = std.mem.replace(u8, expectation, "\n", "↩\n", &buffer);
        std.debug.print("\nExpectation in the {f} (highlighting omitted):\n{s}", .{ area.toRegion(), buffer });
        std.debug.print("\nActual frame:\n{f}", .{self.formatArea(area, .actual)});
        std.debug.print("\nDifference (from actual frame):\n{f}", .{diff.formatArea(area, .diff)});
        return error.TestExpectedEqual;
    }
}

fn diffInArea(self: Self, expected_frame: Self, area: ComparingArea) !?Self {
    var has_difference = false;
    var diff: Self = .empty;
    const region = area.toRegion();
    var cells = region.cells();
    while (cells.next()) |cell| {
        const r = cell.row - 1;
        const c = cell.col - 1;
        const actual_codepoint = self.sprites[r][c].codepoint;
        const expected_codepoint = expected_frame.sprites[r][c].codepoint;
        if (!isEqual(actual_codepoint, expected_codepoint)) {
            diff.sprites[r][c].codepoint = actual_codepoint;
            has_difference = true;
        }
    }
    return if (has_difference) diff else null;
}

fn parse(str: []const u8, region: p.Region) !Self {
    var frame: Self = .empty;
    var r: usize = region.top_left.row - 1;
    var itr = std.mem.splitScalar(u8, str, '\n');
    while (itr.next()) |line| {
        var c: usize = region.top_left.col - 1;
        const view = try std.unicode.Utf8View.init(line);
        var codepoints = view.iterator();
        while (codepoints.nextCodepoint()) |codepoint| {
            frame.sprites[r][c].codepoint = codepoint;
            c += 1;
        }
        r += 1;
    }
    return frame;
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
        0, ' ', space_symbol, zero_symbol => true,
        else => false,
    };
}
