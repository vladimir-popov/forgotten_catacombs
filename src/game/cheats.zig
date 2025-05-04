const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

pub const Cheat = union(enum) {
    pub const Tag = std.meta.Tag(Cheat);
    pub const count = std.meta.fields(Tag).len;

    dump_vector_field,
    move_player_to_ladder_up,
    move_player_to_ladder_down,
    turn_light_on,
    turn_light_off,
    // Moves the player to the point on the screen
    goto: p.Point,
    set_health: u8,

    pub fn init(tag: Tag, args: []const u8) ?Cheat {
        switch (tag) {
            .goto => {
                var itr = std.mem.splitScalar(
                    u8,
                    std.mem.trim(u8, args, " "),
                    ' ',
                );
                if (itr.next()) |a_str|
                    if (tryParseU8(a_str)) |a|
                        if (itr.next()) |b_str|
                            if (tryParseU8(b_str)) |b| {
                                return .{ .goto = p.Point.init(a, b) };
                            };
            },
            .set_health => if (tryParseU8(args)) |hp| {
                return .{ .set_health = hp };
            },
            .dump_vector_field => return .dump_vector_field,
            .move_player_to_ladder_up => return .move_player_to_ladder_up,
            .move_player_to_ladder_down => return .move_player_to_ladder_down,
            .turn_light_on => return .turn_light_on,
            .turn_light_off => return .turn_light_off,
        }
        return null;
    }

    fn tryParseU8(str: []const u8) ?u8 {
        return std.fmt.parseInt(
            u8,
            std.mem.trim(u8, str, " "),
            10,
        ) catch null;
    }

    pub inline fn allAsStrings() [count][]const u8 {
        var strings: [count][]const u8 = undefined;
        inline for (std.meta.fields(Tag), 0..) |f, i| {
            const tag: Tag = @enumFromInt(f.value);
            strings[i] = toString(tag);
        }
        std.mem.sort([]const u8, &strings, {}, strLessThan);
        return strings;
    }
    fn strLessThan(_: void, lhs: []const u8, rhs: []const u8) bool {
        return std.mem.order(u8, lhs, rhs) == .lt;
    }

    pub inline fn toString(comptime self: Cheat.Tag) []const u8 {
        comptime {
            return switch (self) {
                .dump_vector_field => "dump vectors",
                .goto => "goto",
                .move_player_to_ladder_down => "down ladder",
                .move_player_to_ladder_up => "up ladder",
                .set_health => "set health",
                .turn_light_off => "light off",
                .turn_light_on => "light on",
            };
        }
    }

    pub fn parse(str: []const u8) ?Cheat {
        inline for (std.meta.fields(Tag)) |f| {
            const tag: Tag = @enumFromInt(f.value);
            const tag_str = toString(tag);
            if (std.mem.startsWith(u8, str, tag_str)) {
                return Cheat.init(tag, str[tag_str.len..]);
            }
        }
        return null;
    }

    pub fn toAction(self: Cheat, session: *const g.GameSession) ?g.Action {
        switch (self) {
            .move_player_to_ladder_up => {
                var itr = session.level.query().get2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .up) {
                        return movePlayerToPoint(tuple[2].point);
                    }
                }
            },
            .move_player_to_ladder_down => {
                var itr = session.level.query().get2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .down) {
                        return movePlayerToPoint(tuple[2].point);
                    }
                }
            },
            .goto => |goto| {
                const screen_corner = session.viewport.region.top_left;
                return movePlayerToPoint(.{
                    .row = goto.row + screen_corner.row,
                    .col = goto.col + screen_corner.col,
                });
            },
            else => return null,
        }
        return null;
    }

    inline fn movePlayerToPoint(place: p.Point) g.Action {
        return .{ .move = g.Action.Move{ .target = .{ .new_place = place } } };
    }
};

test "list of all cheats in string form" {
    for (Cheat.allAsStrings()) |cheat_str| {
        std.debug.print("{s}\n", .{cheat_str});
    }
}

test "light on" {
    try std.testing.expectEqual(.turn_light_on, Cheat.parse("light on"));
}

test "goto" {
    try std.testing.expectEqual(Cheat{ .goto = p.Point.init(2, 3) }, Cheat.parse("goto 2 3"));
}

test "set health" {
    try std.testing.expectEqual(Cheat{ .set_health = 42 }, Cheat.parse("set health  42"));
}
