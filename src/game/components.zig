const std = @import("std");

pub const Position = struct { row: u8, col: u8 };

pub const Health = struct { health: u8 };

pub const Sprite = struct { letter: []const u8 };

pub const AllComponents = .{ Position, Health, Sprite };
