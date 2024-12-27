//! The placement abstraction is used to calculate visibility of the objects on
//! the level. It's kind of compromise, because of true ray trace is a very
//! hard operation for the playdate.
//! All placements of the level are stored as a graph, where nodes are placements, and
//! edges are doorways.
const std = @import("std");
const g = @import("../game_pkg.zig");
const d = g.dungeon;
const p = g.primitives;

pub const Doorway = struct {
    placement_from: Placement,
    placement_to: Placement,
    // must be set late on level initialization
    door_id: g.Entity = 0,

    pub fn format(
        self: Doorway,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print(
            "Doorway(id: {d}; from {any}; to: {any})",
            .{ self.door_id, self.placement_from, self.placement_to },
        );
    }

    pub inline fn oppositePlacement(self: Doorway, placement: Placement) ?Placement {
        if (self.placement_from.eql(placement)) {
            return self.placement_to;
        } else if (self.placement_to.eql(placement)) {
            return self.placement_from;
        } else {
            return null;
        }
    }
};

/// The tagged union of the pointers to the possible placement implementations.
pub const Placement = union(enum) {
    pub const DoorwaysIterator = std.AutoHashMap(p.Point, void).KeyIterator;

    area: *Area,
    passage: *Passage,
    room: *Room,

    pub fn createArea(arena: *std.heap.ArenaAllocator, region: p.Region) !*Area {
        const alloc = arena.allocator();
        const area = try alloc.create(Area);
        area.* = Area.init(alloc, region);
        return area;
    }

    pub fn createRoom(arena: *std.heap.ArenaAllocator, region: p.Region) !*Room {
        const alloc = arena.allocator();
        const room = try alloc.create(Room);
        room.* = .{
            .region = region,
            .doorways = std.AutoHashMap(p.Point, void).init(alloc),
        };
        return room;
    }

    pub fn createPassage(arena: *std.heap.ArenaAllocator) !*Passage {
        const alloc = arena.allocator();
        const passage = try alloc.create(Passage);
        passage.* = .{
            .turns = std.ArrayList(Passage.Turn).init(alloc),
            .doorways = std.AutoHashMap(p.Point, void).init(alloc),
        };
        return passage;
    }

    pub inline fn eql(self: Placement, other: Placement) bool {
        if (@intFromEnum(self) != @intFromEnum(other)) return false;
        return switch (self) {
            .area => self.area == other.area,
            .room => self.room == other.room,
            .passage => self.passage == other.passage,
        };
    }

    /// Returns true if this placement contains the passed place.
    /// The borders are included, but the inner rooms of the area are not.
    pub fn contains(self: Placement, place: p.Point) bool {
        switch (self) {
            .area => |a| return a.contains(place),
            .room => |r| return r.region.containsPoint(place),
            .passage => |ps| return ps.isPartOfThisPassage(place),
        }
    }

    pub inline fn doorways(self: Placement) DoorwaysIterator {
        return switch (self) {
            .area => |area| area.doorways.keyIterator(),
            .room => |room| room.doorways.keyIterator(),
            .passage => |ps| ps.doorways.keyIterator(),
        };
    }

    pub fn addDoor(self: Placement, place: p.Point) !void {
        switch (self) {
            .area => try self.area.doorways.put(place, {}),
            .room => try self.room.doorways.put(place, {}),
            .passage => try self.passage.doorways.put(place, {}),
        }
    }

    pub fn randomPlace(self: Placement, rand: std.Random) p.Point {
        return switch (self) {
            .area => self.area.randomPlace(rand),
            .room => self.room.randomPlace(rand),
            .passage => self.passage.randomPlace(rand),
        };
    }
};

/// The square placement including the border. Can contain the inner rooms,
/// which should not cross each other or the border of this area.
pub const Area = struct {
    /// The region of this area including the borders
    region: p.Region,
    doorways: std.AutoHashMap(p.Point, void),
    inner_rooms: std.ArrayList(*Room),

    pub fn init(arena: *std.heap.ArenaAllocator, region: p.Region) Area {
        return .{
            .region = region,
            .doorways = std.AutoHashMap(p.Point, void).init(arena.allocator()),
            .inner_rooms = std.ArrayList(*Room).init(arena.allocator()),
        };
    }

    pub fn format(
        self: Area,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Area({any}; inner rooms: [", .{self.region});
        for (self.inner_rooms.items) |ir|
            try writer.print("{any};", .{ir});
        try writer.print("])", .{});
    }

    /// Returns true if the place is inside the area or on its border, but not
    /// inside the inner rooms.
    pub fn contains(self: Area, place: p.Point) bool {
        if (!self.region.containsPoint(place)) return false;
        for (self.inner_rooms.items) |ir| {
            if (ir.region.containsPointInside(place)) return false;
        }
        return true;
    }

    /// Returns true if the place is inside one of the inner room of the area.
    pub fn isInsideInnerRoom(self: Area, place: p.Point) bool {
        for (self.inner_rooms.items) |ir| {
            if (ir.innerRegion().containsPoint(place)) return true;
        }
        return false;
    }

    // TODO: should not return places from the inner rooms
    pub fn randomPlace(self: Area, rand: std.Random) p.Point {
        return .{
            .row = self.region.top_left.row + rand.uintLessThan(u8, self.region.rows - 2) + 1,
            .col = self.region.top_left.col + rand.uintLessThan(u8, self.region.cols - 2) + 1,
        };
    }

    pub fn addRoom(self: *Area, region: p.Region, door: p.Point) !*Room {
        const alloc = self.inner_rooms.allocator;
        const room = try alloc.create(Room);
        room.* = Room.initAsInner(alloc, region, self);
        try room.doorways.put(door, {});
        try self.inner_rooms.append(room);
        try self.doorways.put(door, {});
        return room;
    }
};

pub const Room = struct {
    /// The region of the room including the borders
    region: p.Region,
    doorways: std.AutoHashMap(p.Point, void),
    host_area: ?*const Area = null,

    pub fn init(alloc: std.mem.Allocator, region: p.Region) Room {
        return .{
            .region = region,
            .doorways = std.AutoHashMap(p.Point, void).init(alloc),
        };
    }

    pub fn initAsInner(alloc: std.mem.Allocator, region: p.Region, host: *const Area) Room {
        return .{
            .region = region,
            .doorways = std.AutoHashMap(p.Point, void).init(alloc),
            .host_area = host,
        };
    }

    pub fn format(
        self: Room,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        try writer.print("Room({any}; doorways: [", .{self.region});
        var itr = self.doorways.keyIterator();
        while (itr.next()) |doorway|
            try writer.print("{any};", .{doorway.*});
        try writer.print("])", .{});
    }

    /// Returns the region inside the room (exclude borders).
    pub fn innerRegion(self: Room) p.Region {
        return .{
            .top_left = .{ .row = self.region.top_left.row + 1, .col = self.region.top_left.col + 1 },
            .rows = self.region.rows - 2,
            .cols = self.region.cols - 2,
        };
    }

    pub fn randomPlace(self: Room, rand: std.Random) p.Point {
        return .{
            .row = self.region.top_left.row + rand.uintLessThan(u8, self.region.rows - 2) + 1,
            .col = self.region.top_left.col + rand.uintLessThan(u8, self.region.cols - 2) + 1,
        };
    }
};

pub const Passage = struct {
    pub const Turn = struct {
        place: p.Point,
        to_direction: p.Direction,
        pub fn format(
            self: Turn,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("Turn(at {any} to {s})", .{ self.place, @tagName(self.to_direction) });
        }

        pub fn corner(self: Turn, from_direction: p.Direction) p.Point {
            return self.place.movedTo(from_direction).movedTo(self.to_direction.opposite());
        }
    };

    // the last turn - is a place where the passage is ended, the turn direction is not important there.
    turns: std.ArrayList(Turn),
    doorways: std.AutoHashMap(p.Point, void),

    pub fn format(
        self: Passage,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        try writer.print("Passage({any}; doorways: ", .{self.turns.items});
        var itr = self.doorways.keyIterator();
        while (itr.next()) |doorway|
            try writer.print("{any};", .{doorway.*});
        try writer.print(")", .{});
    }

    /// Returns true if the passed place is inside this passage, or on the wall of
    /// this passage.
    pub fn isPartOfThisPassage(self: Passage, place: p.Point) bool {
        var prev = self.turns.items[0];
        for (self.turns.items[1..]) |curr| {
            if (curr.corner(prev.to_direction).eql(place)) {
                return true;
            } else if (prev.to_direction.isHorizontal()) {
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
};

test "places iterator" {
    // given:
    //             turn
    // Entrance o---o
    //              |
    //              o
    //            Exit
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const passage = Placement.createPassage(&arena);

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
