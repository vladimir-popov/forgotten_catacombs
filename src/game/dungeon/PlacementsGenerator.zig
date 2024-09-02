//! Set of methods to create in the dungeon passages, rooms, and doors between them.
//! This module doesn't mark up the dungeon, and doesn't choose places for the rooms.
const std = @import("std");
const g = @import("game.zig");
const p = g.primitives;

const Dungeon = g.Dungeon;
const Room = g.Dungeon.Room;
const Passage = g.Dungeon.Passage;
const Cell = g.Dungeon.Cell;

const log = std.log.scoped(.placements_generator);

const DungeonGenerator = @This();

pub const Error = error{
    NoSpaceForDoor,
    PassageCantBeCreated,
};

/// Configuration of the simple rooms.
const SimpleRoomOpts = struct {
    /// Minimal rows count in the room
    min_rows: u8 = 5,
    /// Minimal columns count in the room
    min_cols: u8 = 5,
    /// Minimal scale rate to prevent too small rooms
    min_scale: f16 = 0.6,
    /// This is rows/cols ratio of the square.
    /// In case of ascii graphics it's not 1.0
    square_ratio: f16 = 0.4,

    /// Minimal area of the room
    inline fn minArea(generator: SimpleRoomOpts) u8 {
        return generator.dungeon.min_rows * generator.dungeon.min_cols;
    }
};

/// The pointer to the initially empty dungeon
dungeon: *Dungeon,

pub fn generateAndAddRoom(generator: DungeonGenerator, rand: std.Random, region: p.Region) !void {
    const room = try generator.dungeon.generateSimpleRoom(region, rand, .{});
    try generator.dungeon.rooms.append(room);
}

/// Creates floor and walls inside the region with random padding.
/// Also, the count of rows and columns can be randomly reduced too.
///
/// Example of the room inside the 7x7 region with padding 1
/// (the room's region includes the '#' cells):
///
///  ________
/// |       |
/// |       |
/// | ##### |
/// | #   # |
/// | ##### |
/// |       |
/// |       |
/// ---------
fn generateSimpleRoom(generator: DungeonGenerator, region: p.Region, rand: std.Random, opts: SimpleRoomOpts) !Room {
    var room: p.Region = region;
    if (!std.math.approxEqAbs(f16, opts.square_ratio, region.ratio(), 0.1)) {
        // make the region 'more square'
        if (region.ratio() > opts.square_ratio) {
            room.rows = @max(
                opts.min_rows,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.cols)) * opts.square_ratio))),
            );
        } else {
            room.cols = @max(
                opts.min_cols,
                @as(u8, @intFromFloat(@round(@as(f16, @floatFromInt(region.rows)) / opts.square_ratio))),
            );
        }
    }
    var scale: f16 = @floatFromInt(1 + rand.uintLessThan(u16, room.area() - opts.minArea()));
    scale = scale / @as(f16, @floatFromInt(room.area()));
    room.scale(@max(opts.min_scale, scale));

    // generate walls:
    for (room.top_left.row..(room.top_left.row + room.rows)) |r| {
        if (r == room.top_left.row or r == room.bottomRightRow()) {
            generator.dungeon.walls.setRowValue(@intCast(r), room.top_left.col, room.cols, true);
        } else {
            generator.dungeon.walls.set(@intCast(r), @intCast(room.top_left.col));
            generator.dungeon.walls.set(@intCast(r), @intCast(room.bottomRightCol()));
        }
    }
    // generate floor:
    var floor = room;
    floor.top_left.row += 1;
    floor.top_left.col += 1;
    floor.rows -= 2;
    floor.cols -= 2;
    generator.dungeon.floor.setRegionValue(floor, true);

    return room;
}

pub fn createAndAddPassageBetweenRegions(
    generator: DungeonGenerator,
    rand: std.Random,
    r1: *const p.Region,
    r2: *const p.Region,
) !p.Region {
    const direction: p.Direction = if (r1.top_left.row == r2.top_left.row) .right else .down;
    const door1 = try generator.dungeon.findPlaceForDoorInRegionRnd(rand, r1, direction) orelse
        return Error.NoSpaceForDoor;
    const door2 = try generator.dungeon.findPlaceForDoorInRegionRnd(rand, r2, direction.opposite()) orelse
        return Error.NoSpaceForDoor;

    const passage = try generator.dungeon.passages.addOne();
    passage.turns = std.ArrayList(Passage.Turn).init(generator.dungeon.alloc);
    _ = try passage.turnAt(door1, direction);
    if (door1.row != door2.row and door1.col != door2.col) {
        // intersection of the passage from the door 1 and region 1
        var middle1: p.Point = if (direction == .left or direction == .right)
            // left or right
            .{ .row = door1.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = door1.col };

        // intersection of the passage from the region 1 and door 2
        var middle2: p.Point = if (direction == .left or direction == .right)
            // left or right
            .{ .row = door2.row, .col = r1.bottomRightCol() }
        else
            // up or down
            .{ .row = r1.bottomRightRow(), .col = door2.col };

        // try to find better places for turn:
        if (try generator.dungeon.findPlaceForPassageTurn(door1, door2, direction == .left or direction == .right, 0)) |places| {
            middle1 = places[0];
            middle2 = places[1];
        }

        var turn = try passage.turnToPoint(middle1, middle2);

        turn = try passage.turnToPoint(middle2, door2);
    }
    _ = try passage.turnAt(door2, direction);

    try generator.dungeon.digPassage(passage);
    try generator.dungeon.forceCreateDoorAt(door1);
    try generator.dungeon.forceCreateDoorAt(door2);

    return r1.unionWith(r2);
}

/// Trying to find a line between `from` and `to` with `nothing` cells only.
/// Gives up after N attempts to prevent long search.
fn findPlaceForPassageTurn(
    generator: Dungeon,
    init_from: p.Point,
    init_to: p.Point,
    is_horizontal: bool,
    attempt: u8,
) !?struct { p.Point, p.Point } {
    var current_attempt = attempt;
    var stack = std.ArrayList(struct { p.Point, p.Point }).init(generator.dungeon.alloc);
    defer stack.deinit();
    try stack.append(.{ init_from, init_to });
    var middle1: p.Point = undefined;
    var middle2: p.Point = undefined;
    while (stack.popOrNull()) |points| {
        const from = points[0];
        const to = points[1];
        const distance: u8 = if (is_horizontal)
            to.col - from.col
        else
            to.row - from.row;

        if (distance > 4 and current_attempt < 5) {
            if (is_horizontal) {
                middle1.row = from.row;
                middle1.col = distance / 2 + from.col;
                middle2.row = to.row;
                middle2.col = middle1.col;
            } else {
                middle1.row = distance / 2 + from.row;
                middle1.col = from.col;
                middle2.row = middle1.row;
                middle2.col = to.col;
            }
            if (generator.dungeon.isFreeLine(middle1, middle2)) {
                return .{ middle1, middle2 };
            }
            current_attempt += 1;
            try stack.append(.{ from, middle2 });
            try stack.append(.{ middle1, to });
        }
    }
    return null;
}

fn isFreeLine(generator: Dungeon, from: p.Point, to: p.Point) bool {
    const direction: p.Direction = if (from.col == to.col and from.row < to.row)
        .down
    else if (from.col == to.col and from.row > to.row)
        .up
    else if (from.row == to.row and from.col < to.col)
        .right
    else if (from.row == to.row and from.col > to.col)
        .left
    else
        unreachable;
    var cursor = from;
    while (!std.meta.eql(cursor, to)) {
        if (generator.dungeon.isCellAt(cursor, .nothing))
            cursor.move(direction)
        else
            return false;
    }
    return true;
}

fn digPassage(generator: DungeonGenerator, passage: *const Passage) !void {
    var prev: Passage.Turn = passage.turns.items[0];
    for (passage.turns.items[1 .. passage.turns.items.len - 1]) |turn| {
        try generator.dungeon.dig(prev.place, turn.place, prev.to_direction);
        try generator.dungeon.digTurn(turn.place, prev.to_direction, turn.to_direction);
        prev = turn;
    }
    try generator.dungeon.dig(prev.place, passage.turns.getLast().place, prev.to_direction);
}

fn dig(generator: DungeonGenerator, from: p.Point, to: p.Point, direction: p.Direction) !void {
    var point = from;
    while (true) {
        generator.dungeon.createWallAt(point.movedTo(direction.rotatedClockwise(false)));
        generator.dungeon.createWallAt(point.movedTo(direction.rotatedClockwise(true)));
        generator.dungeon.createFloorAt(point);
        if (std.meta.eql(point, to))
            break;
        point.move(direction);
    }
}

fn digTurn(generator: DungeonGenerator, at: p.Point, from: p.Direction, to: p.Direction) !void {
    // wrap the corner by walls
    const reg: p.Region = .{ .top_left = at.movedTo(.up).movedTo(.left), .rows = 3, .cols = 3 };
    var itr = reg.cells();
    while (itr.next()) |cl| {
        generator.dungeon.createWallAt(cl);
    }
    // create the floor in the turn
    try generator.dungeon.forceCreateFloorAt(at);
    try generator.dungeon.forceCreateFloorAt(at.movedTo(from.opposite()));
    try generator.dungeon.forceCreateFloorAt(at.movedTo(to));
}

fn findPlaceForDoorInRegionRnd(
    generator: DungeonGenerator,
    rand: std.Random,
    init_region: *const p.Region,
    side: p.Direction,
) !?p.Point {
    var stack = std.ArrayList(p.Region).init(generator.dungeon.alloc);
    defer stack.deinit();
    try stack.append(init_region.*);
    while (stack.popOrNull()) |region| {
        const place = switch (side) {
            .up => p.Point{
                .row = region.top_left.row,
                .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRightCol()),
            },
            .down => p.Point{
                .row = region.bottomRightRow(),
                .col = rand.intRangeAtMost(u8, region.top_left.col, region.bottomRightCol()),
            },
            .left => p.Point{
                .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRightRow()),
                .col = region.top_left.col,
            },
            .right => p.Point{
                .row = rand.intRangeAtMost(u8, region.top_left.row, region.bottomRightRow()),
                .col = region.bottomRightCol(),
            },
        };
        if (generator.dungeon.findPlaceForDoor(side.opposite(), place, region)) |candidate| {
            if (generator.dungeon.cellAt(candidate)) |cl| {
                switch (cl) {
                    .wall => {
                        return candidate;
                    },
                    else => {},
                }
            }
        }
        // try to find in the different parts of the region:
        var new_regions: [2]?p.Region = .{ null, null };
        if (side == .up or side == .down) {
            new_regions = if (rand.boolean())
                .{ region.cropVerticallyTo(place.col), region.cropVerticallyAfter(place.col) }
            else
                .{ region.cropVerticallyAfter(place.col), region.cropVerticallyTo(place.col) };
        } else {
            new_regions = if (rand.boolean())
                .{ region.cropHorizontallyTo(place.row), region.cropHorizontallyAfter(place.row) }
            else
                .{ region.cropHorizontallyAfter(place.row), region.cropHorizontallyTo(place.row) };
        }
        for (new_regions) |new_region| {
            if (new_region) |reg| {
                reg.validate();
                try stack.append(reg);
            }
        }
    }
    return null;
}

/// Looks for an empty place with the floor.
/// Starting from the `start`, moves in the `direction` till the first floor cell right after the
/// single wall.
/// Returns the found place or null.
fn findPlaceForDoor(generator: Dungeon, direction: p.Direction, start: p.Point, region: p.Region) ?p.Point {
    var place = start;
    while (region.containsPoint(place)) {
        if (generator.dungeon.cellAt(place)) |cl| {
            switch (cl) {
                .nothing => {},
                .wall => {
                    if (!generator.dungeon.isCellAt(place.movedTo(direction), .floor)) {
                        return null;
                    }
                    // check that no one door near
                    if (generator.dungeon.isCellAt(place.movedTo(direction.rotatedClockwise(true)), .door)) {
                        return null;
                    }
                    if (generator.dungeon.isCellAt(place.movedTo(direction.rotatedClockwise(false)), .door)) {
                        return null;
                    }
                    return place;
                },
                else => {
                    return null;
                },
            }
        } else {
            return null;
        }
        place.move(direction);
    }
    return null;
}

test "generate a simple room" {
    // given:
    const Rows = 12;
    const Cols = 12;
    const region = p.Region{ .top_left = .{ .row = 2, .col = 2 }, .rows = 8, .cols = 8 };

    var dungeon = try Dungeon.init(std.testing.allocator);
    defer dungeon.deinit();

    const generator = DungeonGenerator{ .dungeon = &dungeon };

    // when:
    const room = try generator.generateSimpleRoom(region, std.crypto.random, .{});

    // then:
    try std.testing.expect(region.containsRegion(room));
    for (0..Rows) |r_idx| {
        const r: u8 = @intCast(r_idx + 1);
        for (0..Cols) |c_idx| {
            const c: u8 = @intCast(c_idx + 1);
            errdefer std.debug.print("r:{d} c:{d}\n", .{ r, c });

            const cell = generator.dungeon.cellAt(.{ .row = r, .col = c });
            if (room.containsPoint(.{ .row = r, .col = c })) {
                const expect_wall =
                    (r == room.top_left.row or r == room.bottomRightRow() or
                    c == room.top_left.col or c == room.bottomRightCol());
                if (expect_wall) {
                    try std.testing.expectEqual(.wall, cell);
                } else {
                    try std.testing.expectEqual(.floor, cell);
                }
            } else {
                try std.testing.expectEqual(.nothing, cell);
            }
        }
    }
}

test "find a place for door inside the room starting outside" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const generator = DungeonGenerator{ .dungeon = &dungeon };
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = generator.findPlaceForDoor(
        .right,
        p.Point{ .row = 2, .col = 1 },
        region,
    );
    const unexpected = generator.findPlaceForDoor(
        .right,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 2, .col = 2 }, expected.?);
    try std.testing.expect(unexpected == null);
}

test "find a place for door inside the room starting on the wall" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const generator = DungeonGenerator{ .dungeon = &dungeon };
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const expected = generator.findPlaceForDoor(
        .down,
        p.Point{ .row = 1, .col = 3 },
        region,
    );
    const unexpected = generator.findPlaceForDoor(
        .down,
        p.Point{ .row = 1, .col = 1 },
        region,
    );

    // then:
    try std.testing.expectEqualDeep(p.Point{ .row = 1, .col = 3 }, expected.?);
    try std.testing.expect(unexpected == null);
}
test "find a random place for the door on the left side" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const generator = DungeonGenerator{ .dungeon = &dungeon };
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_left = try generator.findPlaceForDoorInRegionRnd(std.crypto.random, &region, .left);

    // then:
    errdefer std.debug.print("place left {any}\n", .{place_left});
    try std.testing.expectEqual(2, place_left.?.col);
    try std.testing.expect(2 <= place_left.?.row and place_left.?.row <= 3);
}

test "find a random place for the door on the bottom side" {
    // given:
    const str =
        \\ ####
        \\ #..#
        \\ #..#
        \\ ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const generator = DungeonGenerator{ .dungeon = &dungeon };
    const region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 4, .cols = 5 };

    // when:
    const place_bottom = try generator.findPlaceForDoorInRegionRnd(std.crypto.random, &region, .down);

    // then:
    errdefer std.debug.print("place bottom {any}\n", .{place_bottom});
    try std.testing.expectEqual(4, place_bottom.?.row);
    try std.testing.expect(3 <= place_bottom.?.col and place_bottom.?.col <= 4);
}

test "create passage between two rooms" {
    // given:
    const Rows = 4;
    const Cols = 12;
    const str =
        \\ ####   ####
        \\ #..#   #..#
        \\ #..#   #..#
        \\ ####   ####
    ;
    errdefer std.debug.print("{s}\n", .{str});
    var dungeon = try Dungeon.parse(std.testing.allocator, str);
    defer dungeon.deinit();
    const generator = DungeonGenerator{ .dungeon = &dungeon };
    const expected_region = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = Cols };
    const r1 = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = Rows, .cols = 6 };
    const r2 = p.Region{ .top_left = .{ .row = 1, .col = 7 }, .rows = Rows, .cols = Cols - 6 };

    // when:
    const region = try generator.createAndAddPassageBetweenRegions(std.crypto.random, &r1, &r2);

    // then:
    try std.testing.expectEqualDeep(expected_region, region);
    const passage: Passage = generator.dungeon.passages.items[0];
    errdefer std.debug.print("Passage: {any}\n", .{passage.turns.items});
    try std.testing.expect(passage.turns.items.len >= 2);
}
