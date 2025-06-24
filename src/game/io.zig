const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

pub const Entity = struct {
    id: g.Entity,
    components: g.components.Components,
};

pub const Level = struct {
    depth: u8,
    dungeon_seed: u64,
    entities: []const Entity,
    /// An array of arrays of toggled indexes inside the one row of the BitSet
    visited_places: [][]usize,
    remembered_objects: []struct { p.Point, g.Entity },
};

pub const GameSession = struct {
    seed: u64,
    next_entity: g.Entity,
    max_depth: u8,
    player: Entity,
};
