const std = @import("std");
const ecs = @import("ecs.zig");

pub const Position = struct { row: u8, col: u8 };

pub const Health = struct { health: u8 };

pub const Floor = struct { entities: []const ecs.Entity = undefined };

pub const AllComponents = .{ Position, Health, Floor };
