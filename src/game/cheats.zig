const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const c = g.components;

pub const Cheat = union(enum) {
    move_player_to_ladder_up,
    move_player_to_ladder_down,
    // Moves the player to the point on the screen
    move_player: p.Point,

    pub fn parse(str: []const u8) ?Cheat {
        if (std.mem.eql(u8, "move to entrance", str)) {
            return .move_player_to_ladder_up;
        }
        if (std.mem.eql(u8, "move to exit", str)) {
            return .move_player_to_ladder_down;
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
        }
        return null;
    }

    inline fn movePlayerToPoint(place: p.Point) g.Action {
        return .{ .move = g.Action.Move{ .target = .{ .new_place = place } } };
    }
};
