//! This module contains logic to handle actions of the player or NPC.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.actions);

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
    /// Do nothing, as example, when trying to move to the wall
    do_nothing,
    /// Skip the round
    wait,
    /// An entity is going to move in the direction
    move: Move,
    /// An entity is going to open a door
    open: struct { id: g.Entity, place: p.Point },
    /// An entity is going to close a door
    close: struct { id: g.Entity, place: p.Point },
    /// An entity to hit
    hit: g.Entity,
    /// The id of an item that someone is going to take from the floor
    pickup: g.Entity,
    /// The id of a potion to drink
    drink: g.Entity,
    /// The id of a food to eat
    eat: g.Entity,
    /// The player moves from the level to another level
    move_to_level: c.Ladder,
    /// Change the state of the entity to sleep
    go_sleep: g.Entity,
    /// Change the state of the entity to chill
    chill: g.Entity,
    /// Change the state of the entity to hunt
    get_angry: g.Entity,
    //
    open_inventory,
    //
    trade: *c.Shop,

    pub fn priority(self: Action) u8 {
        return switch (self) {
            .do_nothing => 0,
            .move_to_level => 10,
            .hit => 9,
            .pickup => 5,
            else => 1,
        };
    }

    pub fn toString(action: Action) []const u8 {
        return switch (action) {
            .close => "Close",
            .drink => "Drink",
            .eat => "Eat",
            .hit => "Attack",
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => "Go up",
                .down => "Go down",
            },
            .open => "Open",
            .open_inventory => "Inventory",
            .pickup => "Pickup",
            .trade => "Trade",
            .wait => "Wait",
            .get_angry, .chill, .go_sleep, .do_nothing, .move => "???",
        };
    }

    pub fn eql(self: Action, maybe_other: ?Action) bool {
        if (maybe_other) |other| {
            return std.meta.eql(self, other);
        } else {
            return false;
        }
    }
};
