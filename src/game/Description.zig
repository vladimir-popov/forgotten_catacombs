const std = @import("std");
const g = @import("game_pkg.zig");

const Description = @This();

name: []const u8,
description: []const []const u8 = &.{},

pub const closed_door: Description = .{ .name = "Closed door" };
pub const club: Description = .{ .name = "Club" };
pub const ladder_down: Description = .{ .name = "Ladder down" };
pub const ladder_to_caves: Description = .{ .name = "Ladder to caves" };
pub const ladder_up: Description = .{ .name = "Ladder up" };
pub const opened_door: Description = .{ .name = "Opened door" };
pub const pile: Description = .{ .name = "Pile of items" };
pub const player: Description = .{ .name = "You" };
pub const rat: Description = .{ .name = "Rat" };
pub const scientist: Description = .{ .name = "Scientist" };
pub const teleport: Description = .{ .name = "Teleport" };
pub const torch: Description = .{ .name = "Torch" };
pub const traider: Description = .{ .name = "Traider" };
pub const wharf: Description = .{ .name = "Wharf" };
