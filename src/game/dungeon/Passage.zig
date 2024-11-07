const std = @import("std");
const g = @import("../game_pkg.zig");
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

// the last turn - is a place where the passage is ended, the turn direction is not important there.
turns: std.ArrayList(Turn),
doorways: std.AutoHashMap(p.Point, void),

pub fn init(alloc: std.mem.Allocator) Passage {
    return .{
        .turns = std.ArrayList(Turn).init(alloc),
        .doorways = std.AutoHashMap(p.Point, void).init(alloc),
    };
}

pub fn deinit(self: *Passage) void {
    self.turns.deinit();
    self.doorways.deinit();
}

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

pub fn contains(self: Passage, place: p.Point) bool {
    var prev = self.turns.items[0];
    for (self.turns.items[1..]) |curr| {
        if (prev.to_direction.isHorizontal()) {
            if (isOnHorizontalLine(prev.place, curr.place, place) or
                isOnHorizontalLine(prev.place.movedTo(.up), curr.place.movedTo(.up), place) or
                isOnHorizontalLine(prev.place.movedTo(.down), curr.place.movedTo(.down), place))
                return true;
        } else {
            if (isOnVerticalLine(prev.place, curr.place, place) or
                isOnVerticalLine(prev.place.movedTo(.left), curr.place.movedTo(.left), place) or
                isOnVerticalLine(prev.place.movedTo(.right), curr.place.movedTo(.right), place))
                return true;
        }

        prev = curr;
    }
    return false;
}

inline fn isOnHorizontalLine(p1: p.Point, p2: p.Point, place: p.Point) bool {
    return place.row == p1.row and isBetween(p1.col, p2.col, place.col);
}

inline fn isOnVerticalLine(p1: p.Point, p2: p.Point, place: p.Point) bool {
    return place.col == p1.col and isBetween(p1.row, p2.row, place.row);
}

inline fn isBetween(x: u8, y: u8, value: u8) bool {
    return @min(x, y) <= value and value <= @max(x, y);
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

pub const PlacesIterator = struct {
    turns: std.ArrayList(Turn),
    last_turn_idx: u8 = 0,
    current_place: p.Point,

    pub fn next(self: *PlacesIterator) ?p.Point {
        if (self.last_turn_idx == (self.turns.items.len - 1)) return null;

        const next_turn = self.turns.items[self.last_turn_idx + 1];
        if (self.current_place.eql(next_turn.place)) self.last_turn_idx += 1;
        const turn = self.turns.items[self.last_turn_idx];
        const place = self.current_place;
        self.current_place.move(turn.to_direction);
        return place;
    }
};

pub fn places(self: Passage) PlacesIterator {
    return .{ .turns = self.turns, .current_place = self.turns.items[0].place };
}

test "places iterator" {
    // given:
    //             turn
    // Entrance o---o
    //              |
    //              o
    //            Exit
    var passage = Passage.init(std.testing.allocator);
    defer passage.deinit();
    _ = try passage.turnAt(.{ .row = 1, .col = 1 }, .right);
    _ = try passage.turnAt(.{ .row = 1, .col = 3 }, .down);
    _ = try passage.turnAt(.{ .row = 3, .col = 3 }, .down);

    const expected_places: [5]p.Point = .{
        .{ .row = 1, .col = 1 },
        .{ .row = 1, .col = 2 },
        .{ .row = 1, .col = 3 },
        .{ .row = 2, .col = 3 },
        .{ .row = 3, .col = 3 },
    };
    var actual_places = std.ArrayList(p.Point).init(std.testing.allocator);
    defer actual_places.deinit();

    // when:
    var itr = passage.places();
    while (itr.next()) |place| {
        try actual_places.append(place);
    }

    // then:
    try std.testing.expectEqualSlices(p.Point, &expected_places, actual_places.items);
}
