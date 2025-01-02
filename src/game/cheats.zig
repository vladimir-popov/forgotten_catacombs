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
    move_player: p.Point,

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
                .move_player => "go to",
                .move_player_to_ladder_down => "down ladder",
                .move_player_to_ladder_up => "up ladder",
                .turn_light_off => "light off",
                .turn_light_on => "light on",
            };
        }
    }

    pub fn parse(str: []const u8) ?Cheat {
        inline for (std.meta.fields(Tag)) |f| {
            const tag: Tag = @enumFromInt(f.value);
            if (std.mem.eql(u8, str, toString(tag)) and tag != .move_player) {
                return @as(Cheat, tag);
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
            .move_player => |point_on_screen| {
                const screen_corner = session.render.viewport.region.top_left;
                return movePlayerToPoint(.{
                    .row = point_on_screen.row + screen_corner.row,
                    .col = point_on_screen.col + screen_corner.col,
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
