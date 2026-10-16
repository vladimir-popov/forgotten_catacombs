const std = @import("std");
const g = @import("../game_pkg.zig");

const Default = struct {
    pub const Ammo = @import("Ammo.zig");
    pub const Archetypes = @import("Archetypes.zig");
    pub const Armor = @import("Armor.zig");
    pub const Food = @import("Food.zig");
    pub const Other = @import("Other.zig");
    pub const Potions = @import("Potions.zig");
    pub const Skills = @import("Skills.zig");
    pub const Stats = @import("Stats.zig");
    pub const Enemies = @import("Enemies.zig");
    pub const Weapons = @import("Weapons.zig");
};

pub const Preset = g.utils.Preset(g.Description, Default);

test "All descriptions should have lines with no more than 35 symbols" {
    var itr = Preset.iterator();
    while (itr.next()) |description| {
        for (description.description) |line| {
            const len = try std.unicode.utf8CountCodepoints(line);
            std.testing.expect(len < 36) catch |err| {
                std.debug.print(
                    "Description {s} has too long line with {d} symbols:\n\"{s}\"\n",
                    .{ description.name, line.len, line },
                );
                return err;
            };
        }
    }
}
