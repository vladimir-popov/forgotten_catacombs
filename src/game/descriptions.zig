const std = @import("std");
const g = @import("game_pkg.zig");

pub const Description = struct {
    /// A short name of the entity.
    name: []const u8,

    // A line should have no more 36 symbols

    /// A short description of the entity.
    description: []const []const u8 = &.{},
};

closed_door: Description = .{ .name = "Closed door" },
club: Description = .{
    .name = "Club",
    .description = &.{
        "A gnarled piece of wood, scarred",
        "from use. Deals blunt damage.",
        "Cheap and easy to use.",
    },
},
food_ration: Description = .{
    .name = "Food ration",
    .description = &.{
        "A compact bundle of preserved food.",
        "Bland and meager, yet designed to",
        "provide steady nourishment over a",
        "long period.",
    },
},
healing_potion: Description = .{
    .name = "A healing potion",
    .description = &.{
        "A brew that glows faintly, as if ",
        "alive. It warms your veins and mends",
        "your wounds instantly.",
    },
},
poisoning_potion: Description = .{
    .name = "A poison",
    .description = &.{
        "A vial filled with a thick, bitter",
        "liquid that smells of decay.",
    },
},
oil_potion: Description = .{
    .name = "Oil",
    .description = &.{
        "Glass bottle filled with viscous oil",
        "Useful as lamp fuel",
    },
},
coctail_molotov: Description = .{
    .name = "Molotov cocktail",
    .description = &.{
        "A dark glass bottle sealed with a",
        "cloth wad soaked in fuel. When it",
        "shatters the dark liquid spatters",
        "and flames leap up",
    },
},
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
oil_lamp: Description = .{
    .name = "Oil lamp",
    .description = &.{
        "A simple metal lamp filled with oil,",
        "its flickering flame casts light",
        "into the darkest corners.",
    },
},
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
    var itr = g.presets.Descriptions.iterator();
    while (itr.next()) |description| {
        for (description.description) |line| {
            const len = try std.unicode.utf8CountCodepoints(line);
            std.testing.expect(len < 37) catch |err| {
                std.debug.print(
                    "Description {s} has too long line with {d} symbols:\n\"{s}\"\n",
                    .{ description.name, line.len, line },
                );
                return err;
            };
        }
    }
}
