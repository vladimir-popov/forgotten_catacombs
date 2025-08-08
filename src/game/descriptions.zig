const std = @import("std");
const g = @import("game_pkg.zig");

pub const Description = struct {
    name: []const u8,
    // a line should have no more 36 symbols
    description: []const []const u8 = &.{},
};

pub const Presets = g.utils.Preset(@This());

closed_door: Description = .{ .name = "Closed door" },
club: Description = .{ .name = "Club" },
healing_potion: Description = .{ .name = "A potion of healing" },
ladder_down: Description = .{ .name = "Ladder down" },
ladder_to_caves: Description = .{ .name = "Entrance to caves" },
ladder_up: Description = .{ .name = "Ladder up" },
opened_door: Description = .{ .name = "Opened door" },
pickaxe: Description = .{ .name = "Pickaxe" },
pile: Description = .{ .name = "Pile of items" },
player: Description = .{ .name = "You" },
rat: Description = .{ .name = "Rat", .description = &.{"Big nasty rat with vicious eyes."} },
scientist: Description = .{ .name = "Scientist" },
teleport: Description = .{ .name = "Teleport" },
torch: Description = .{ .name = "Torch" },
traider: Description = .{ .name = "Traider" },
unknown_key: Description = .{ .name = "Unknown" },
unknown_potion: Description = .{ .name = "Unknown potion" },
wharf: Description = .{ .name = "Wharf" },
