const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

/// All possible notification about significant events in the game.
pub const Notification = union(enum) {
    /// The player successfully hit a target.
    hit: struct {
        /// An enemy hit by the player
        target: g.Entity,
        damage: u8,
    },
    /// The player was hit
    damage: struct {
        /// An enemy hit the player
        actor: g.Entity,
        damage: u8,
    },
    /// An entity step in a trap
    trap: struct {
        name: []const u8,
        damage: u8,
    },
    disarmed_trap,
    /// The player received experience points
    exp: u16,
    level_up,
    /// The enemy dodged
    miss: struct { target: g.Entity },
    /// The player dodged
    dodge: struct { actor: g.Entity },
    /// The quiver is empty
    no_ammo,
    /// The weapon requires different type of the ammo
    wrong_ammo,

    // Max length is 16 symbols
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .hit => |hit| try writer.print("Hit {d}", .{hit.damage}),
            .damage => |dmg| try writer.print("Damage -{d}", .{dmg.damage}),
            .exp => |exp| try writer.print("+{d} EXP", .{exp}),
            .level_up => _ = try writer.write("Level up!"),
            .miss => _ = try writer.write("Miss"),
            .dodge => _ = try writer.write("Dodge"),
            .no_ammo => _ = try writer.write("No ammo!"),
            .trap => |trap| try writer.print("{s} -{d}", .{ trap.name, trap.damage }),
            .wrong_ammo => _ = try writer.write("Wrong ammo!"),
            .disarmed_trap => _ = try writer.write("Disarmed"),
        }
    }
};
