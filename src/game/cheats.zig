const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

const log = std.log.scoped(.cheats);

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
    /// This cheat works only in trading mode, and sets up the amount of money depending on
    /// the active tab:
    ///  - for Buying tab the balance of the shop will be changed;
    ///  - for Selling tab the player's balance will be changed.
    set_money: u8,
    hit: g.Action.Hit,

    pub fn init(tag: Tag, args: []const u8) ?Cheat {
        switch (tag) {
            .goto => {
                var itr = std.mem.tokenizeScalar(u8, args, ' ');
                if (itr.next()) |a_str|
                    if (tryParse(u8, a_str)) |a|
                        if (itr.next()) |b_str|
                            if (tryParse(u8, b_str)) |b| {
                                return .{ .goto = p.Point.init(a, b) };
                            };
                log.warn(
                    \\Wrong arguments '{s}' for 'goto' command. 
                    \\It expects a number of the target row and a number of the target column
                    \\in the dungeon's coordinates.
                ,
                    .{args},
                );
            },
            .set_health => if (tryParse(u8, args)) |hp| {
                return .{ .set_health = hp };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'set health' command. It expects a number value to set.",
                    .{args},
                );
            },
            .set_money => if (tryParse(u8, args)) |money| {
                return .{ .set_money = money };
            } else {
                log.warn(
                    "Wrong arguments '{s}' for 'set money' command. It expects a number value to set.",
                    .{args},
                );
            },
            .hit => {
                var itr = std.mem.tokenizeScalar(u8, args, ' ');
                if (itr.next()) |entity_str| if (g.Entity.parse(entity_str)) |target|
                    if (itr.next()) |value_str| if (tryParse(u8, value_str)) |damage| {
                        return .{
                            .hit = .{
                                .target = target,
                                .by_weapon = .{ .min_damage = damage, .max_damage = damage },
                            },
                        };
                    };
                log.warn(
                    "Wrong arguments '{s}' for 'hit' command. It expects an ID of the target and a damage amount.",
                    .{args},
                );
            },
            .dump_vector_field => return .dump_vector_field,
            .move_player_to_ladder_up => return .move_player_to_ladder_up,
            .move_player_to_ladder_down => return .move_player_to_ladder_down,
            .turn_light_on => return .turn_light_on,
            .turn_light_off => return .turn_light_off,
        }
        return null;
    }

    inline fn tryParse(comptime U: type, str: []const u8) ?U {
        return std.fmt.parseInt(
            U,
            std.mem.trim(u8, str, " \t"),
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
                .hit => "hit",
                .move_player_to_ladder_down => "down ladder",
                .move_player_to_ladder_up => "up ladder",
                .set_health => "set health",
                .set_money => "set money",
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

    pub fn toAction(self: Cheat, session: *g.GameSession) ?g.Action {
        switch (self) {
            .move_player_to_ladder_up => {
                var itr = session.registry.query2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .up) {
                        return movePlayerToPoint(tuple[2].place);
                    }
                }
            },
            .move_player_to_ladder_down => {
                var itr = session.registry.query2(c.Ladder, c.Position);
                while (itr.next()) |tuple| {
                    if (tuple[1].direction == .down) {
                        return movePlayerToPoint(tuple[2].place);
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
            .hit => return .{ .hit = self.hit },
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
