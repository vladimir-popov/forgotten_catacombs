const std = @import("std");
const g = @import("game_pkg.zig");

pub const Description = struct {
    /// A short name of the entity.
    name: []const u8,

    // A line should have no more 36 symbols

    /// A short description of the entity.
    description: []const []const u8 = &.{},
};

pub const Presets = g.utils.Preset(@This());

closed_door: Description = .{ .name = "Closed door" },
club: Description = .{
    .name = "Club",
    .description = &.{
        "A gnarled piece of wood, scarred",
        "from use. Deals blunt damage.",
        "Cheap and easy to use.",
    },
},
healing_potion: Description = .{ .name = "A potion of healing" },
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
opened_door: Description = .{ .name = "Opened door" },
pickaxe: Description = .{
    .name = "Pickaxe",
    .description = &.{
        "Heavy tool for mining stone and ore.",
        "Can double as a crude weapon.",
    },
},
pile: Description = .{
    .name = "Pile of items",
    .description = &.{
        "A heap of miscellaneous gear. Search",
        "it to see what’s useful.",
    },
},
player: Description = .{ .name = "You" },
rat: Description = .{
    .name = "Rat",
    .description = &.{
        "A big, nasty rat with vicious eyes",
        "that thrives in dark corners and",
        "forgotten cellars.",
    },
},
scientist: Description = .{ .name = "Scientist" },
teleport: Description = .{ .name = "Teleport" },
torch: Description = .{
    .name = "Torch",
    .description = &.{
        "Wooden handle, cloth wrap, burning",
        "flame. Lasts until the fire dies.",
    },
},
traider: Description = .{ .name = "Traider" },
unknown_key: Description = .{ .name = "Unknown" },
unknown_potion: Description = .{
    .name = "Unknown potion",
    .description = &.{
        "A swirling liquid of indeterminate",
        "color rests in a vial.",
        "Effect unknown. Use with caution.",
    },
},
wolf: Description = .{
    .name = "Wolf",
    .description = &.{
        "Wild predator. Its fur is smeared",
        "with blood, eyes glinting with",
        "hunger.",
    },
},
wharf: Description = .{ .name = "Wharf" },

test "All descriptions should have lines less that 37 symbols" {
    for (0..Presets.size) |i| {
        const key: Presets.Keys = @enumFromInt(i);
        const description = Presets.get(key);
        for (description.description) |line| {
            const len = try std.unicode.utf8CountCodepoints(line);
            std.testing.expect(len < 37) catch |err| {
                std.debug.print(
                    "Description {t} has too long line with {d} symbols:\n\"{s}\"\n",
                    .{ key, line.len, line },
                );
                return err;
            };
        }
    }
}
