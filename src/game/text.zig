const std = @import("std");
const g = @import("game_pkg.zig");
const empty_description = g.components.Description.empty_description;

pub const names = std.StaticStringMap([]const u8).initComptime(&.{
    .{ "cdr", "Closed door" },
    .{ "clb", "Club" },
    .{ "cldr", "Ladder to caves" },
    .{ "dldr", "Ladder down" },
    .{ "odr", "Opened door" },
    .{ "plr", "You" },
    .{ "rat", "Rat" },
    .{ "scnst", "Scientist" },
    .{ "tprt", "Ladder down" },
    .{ "trch", "Torch" },
    .{ "trdr", "Traider" },
    .{ "uldr", "Ladder up" },
    .{ "whrf", "Wharf" },
});

pub const descriptions = std.StaticStringMap([]const []const u8).initComptime(&.{
    .{ "cdr", empty_description },
    .{ "clb", empty_description },
    .{ "cldr", empty_description },
    .{ "dldr", empty_description },
    .{ "odr", empty_description },
    .{ "plr", empty_description },
    .{ "rat", empty_description },
    .{ "tprt", empty_description },
    .{ "trch", empty_description },
    .{ "uldr", empty_description },
    .{ "whrf", empty_description },
});
