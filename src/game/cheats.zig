const std = @import("std");
const b = @import("base");

pub const Cheat = union(enum) {
    refresh_screen,
    move_player_to_entrance,
    move_player_to_exit,
    // Moves the player to the point on the screen
    move_player: b.Point,

    pub fn parse(str: []const u8) ?Cheat {
        if (std.mem.eql(u8, "refresh", str)) {
            return .refresh_screen;
        }
        if (std.mem.eql(u8, "move to entrance", str)) {
            return .move_player_to_entrance;
        }
        if (std.mem.eql(u8, "move to exit", str)) {
            return .move_player_to_exit;
        }
        return null;
    }
};
