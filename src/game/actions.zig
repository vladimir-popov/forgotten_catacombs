const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const MovePoints = u8;

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = union(enum) {
    pub const Move = struct {
        pub const Target = union(enum) {
            new_place: p.Point,
            direction: p.Direction,
        };
        target: Target,
        keep_moving: bool = false,
    };
    pub const Hit = struct {
        target: g.Entity,
        by_weapon: c.Weapon,
    };
    /// Do nothing, as example, when trying to move to the wall
    do_nothing,
    /// Skip the round
    wait,
    /// Change the state of the entity to sleep
    go_sleep: g.Entity,
    /// Change the state of the entity to chill
    chill: g.Entity,
    /// Change the state of the entity to hunt
    get_angry: g.Entity,
    /// An entity is going to move in the direction
    move: Move,
    /// An entity is going to open a door
    open: g.Entity,
    /// An entity is going to close a door
    close: g.Entity,
    /// An entity which should be hit
    hit: Hit,
    /// An entity is going to take the item
    take: g.Entity,
    /// The player moves from the level to another level
    move_to_level: c.Ladder,

    pub fn toString(action: Action) []const u8 {
        return switch (action) {
            .wait => "Wait",
            .open => "Open",
            .close => "Close",
            .hit => "Attack",
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => "Go up",
                .down => "Go down",
            },
            else => "",
        };
    }
};
