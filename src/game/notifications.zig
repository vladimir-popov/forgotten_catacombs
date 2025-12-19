const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

/// All possible notification about significant events in the game.
pub const Notification = union(enum) {
    /// The player successfully hit a target.
    hit: struct {
        target: g.Entity,
        damage: u8,
        damage_type: c.Effect.Type,
    },
    /// The player was hit
    damage: struct {
        damage: u8,
        damage_type: c.Effect.Type,
    },
    /// The enemy dodged
    miss,
    /// The player dodged
    dodge,
    /// The quiver is empty
    no_ammo,
    /// The weapon requires different type of the ammo
    wrong_ammo,

    // Max length is 20 symbols
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .hit => |hit| try writer.print("Hit {d}", .{hit.damage}),
            .damage => |dmg| try writer.print("Damage -{d}", .{dmg.damage}),
            .miss => _ = try writer.write("Miss!"),
            .dodge => _ = try writer.write("Dodge!"),
            .no_ammo => _ = try writer.write("No ammo!"),
            .wrong_ammo => _ = try writer.write("Wrong ammo!"),
        }
    }
};
