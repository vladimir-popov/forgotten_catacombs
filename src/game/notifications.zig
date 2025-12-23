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
        actor: g.Entity,
        damage: u8,
        damage_type: c.Effect.Type,
    },
    /// The player received experience points
    exp: u16,
    /// The enemy dodged
    miss: struct { target: g.Entity },
    /// The player dodged
    dodge: struct { actor: g.Entity },
    /// The quiver is empty
    no_ammo,
    /// The weapon requires different type of the ammo
    wrong_ammo,

    // Max length is 20 symbols
    pub fn format(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .hit => |hit| try writer.print("Hit {d}", .{hit.damage}),
            .damage => |dmg| {
                // if (dmg.damage_type == .physical)
                //     try writer.print("-{d} damage", .{dmg.damage})
                // else
                //     try writer.print("-{d} {t}", .{ dmg.damage, dmg.damage_type });
                switch (dmg.damage_type) {
                    .heal => try writer.print("Heal +{d}", .{dmg.damage}),
                    .physical => try writer.print("Damage -{d}", .{dmg.damage}),
                    .fire => try writer.print("Fire -{d}", .{dmg.damage}),
                    .acid => try writer.print("Acid -{d}", .{dmg.damage}),
                    .poison => try writer.print("Poison -{d}", .{dmg.damage}),
                }
            },
            .exp => |exp| try writer.print("+{d} EXP", .{exp}),
            .miss => _ = try writer.write("Miss"),
            .dodge => _ = try writer.write("Dodge"),
            .no_ammo => _ = try writer.write("No ammo"),
            .wrong_ammo => _ = try writer.write("Wrong ammo!"),
        }
    }
};
