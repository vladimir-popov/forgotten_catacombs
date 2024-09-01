const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

const Passage = @This();

pub const Turn = struct {
    place: p.Point,
    to_direction: p.Direction,
    pub fn format(
        self: Turn,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Turn(at {any} to {s})", .{ self.place, @tagName(self.to_direction) });
    }
};

turns: std.ArrayList(Turn),

pub fn format(
    self: Passage,
    comptime fmt: []const u8,
    options: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    _ = fmt;
    _ = options;

    try writer.print("Passage({any})", .{self.turns.items});
}

pub fn deinit(self: Passage) void {
    self.turns.deinit();
}

pub fn turnAt(self: *Passage, place: p.Point, direction: p.Direction) !Turn {
    const turn: Turn = .{ .place = place, .to_direction = direction };
    try self.turns.append(turn);
    return turn;
}

pub fn turnToPoint(self: *Passage, at: p.Point, to: p.Point) !Turn {
    const direction: p.Direction = if (at.row == to.row)
        if (at.col < to.col) .right else .left
    else if (at.row < to.row) .down else .up;
    return try self.turnAt(at, direction);
}

pub fn randomPlace(passage: Passage, rand: std.Random) p.Point {
    const from_idx = rand.uintLessThan(usize, passage.turns.items.len - 1);
    const from_turn = passage.turns.items[from_idx];
    const to_turn = passage.turns.items[from_idx + 1];
    if (from_turn.to_direction == .left or from_turn.to_direction == .right) {
        return .{
            .row = from_turn.place.row,
            .col = rand.intRangeAtMost(
                u8,
                @min(from_turn.place.col, to_turn.place.col),
                @max(from_turn.place.col, to_turn.place.col),
            ),
        };
    } else {
        return .{
            .row = rand.intRangeAtMost(
                u8,
                @min(from_turn.place.row, to_turn.place.row),
                @max(from_turn.place.row, to_turn.place.row),
            ),
            .col = from_turn.place.col,
        };
    }
}

