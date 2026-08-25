//! This module contains logic to handle actions of the player or NPC.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.actions);

pub const MovePoints = u8;

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = struct {
    // Zig always copies the tagged union on stack for switch statement.
    // The Action is to big for extra copies on Playdate where we have only ~10kb stack size in total.
    // This is why we have to use this synthetic version of the tagged union.

    pub const Payload = union {
        pub const Move = struct {
            pub const Target = union(enum) {
                /// A place in the dungeon (1-based)
                new_place: p.Point,
                direction: p.Direction,

                pub fn asPlace(self: Target, from_position: p.Point) p.Point {
                    return switch (self) {
                        .direction => |direction| from_position.movedTo(direction),
                        .new_place => |place| place,
                    };
                }
            };
            target: Target,
        };

        pub const Door = struct { id: g.Entity, place: p.Point };

        /// Skip the round
        wait: void,
        /// An entity is going to move in the direction
        move: Move,
        /// An entity is going to open a door
        open: Door,
        /// An entity is going to close a door
        close: Door,
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
        open_inventory: void,
        //
        modify_recognize: void,
        //
        step_in_trap: struct { trap_entity: g.Entity, moving_target: Move.Target },
        //
        trade: g.Entity,
        //
        disarm_trap: g.Entity,
    };

    pub const Tag = blk: {
        const fields = @typeInfo(Payload).@"union".fields;
        const TagInt = std.math.IntFittingRange(0, fields.len - 1);
        var names: [fields.len][]const u8 = undefined;
        var values: [fields.len]TagInt = undefined;
        for (fields, 0..) |field, i| {
            names[i] = field.name;
            values[i] = i;
        }
        break :blk @Enum(
            TagInt,
            .exhaustive,
            &names,
            &values,
        );
    };

    tag: Tag,
    payload: Payload,

    pub fn action(comptime tag: Tag, payload: PayloadType(tag)) Action {
        return .{ .tag = tag, .payload = @unionInit(Payload, @tagName(tag), payload) };
    }

    pub fn set(self: *Action, comptime tag: Tag, payload: PayloadType(tag)) void {
        self.tag = tag;
        self.payload = @unionInit(Payload, @tagName(tag), payload);
    }

    fn PayloadType(comptime tag: Tag) type {
        return @typeInfo(Payload).@"union".fields[@intFromEnum(tag)].type;
    }

    pub fn priority(self: Action) u8 {
        return switch (self.tag) {
            .hit => 10,
            .move_to_level => 9,
            .disarm_trap => 8,
            .pickup => 5,
            .modify_recognize, .trade => 4,
            else => 1,
        };
    }

    pub fn toString(act: Action) []const u8 {
        return switch (act.tag) {
            .close => "Close",
            .drink => "Drink",
            .eat => "Eat",
            .hit => "Attack",
            .move_to_level => switch (act.payload.move_to_level.direction) {
                .up => "Go up",
                .down => "Go down",
            },
            .open => "Open",
            .open_inventory => "Inventory",
            .pickup => "Pickup",
            .trade => "Trade",
            .wait => "Wait",
            .modify_recognize => "Mod/Rec",
            .disarm_trap => "Disarm",
            .get_angry, .chill, .go_sleep, .move, .step_in_trap => "???",
        };
    }
};
