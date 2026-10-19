const std = @import("std");
const Type = std.builtin.Type;
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.events);

/// Deferred notifications about game-state changes that need coordinated
/// handling by `GameSession` or its owned subsystems.
///
/// `GameSession` queues these while systems run and dispatches them after the
/// current tick. This keeps follow-up work, such as initializing a new mode or
/// synchronizing level and viewport state after player movement, out of the
/// operation that caused the change.
pub const Event = union(enum) {
    const Tag = @typeInfo(Event).@"union".tag_type.?;

    /// Starts loading or generating the destination level after ladder travel.
    level_changed: ChangingLevel,

    /// Updates the level's player placement and Dijkstra map, and keeps the
    /// viewport positioned around the player. NPC movement is not published.
    player_moved: PlayerMoved,

    /// Requests `GameSession` to initialize the requested game mode.
    mode_changed: ModeChanged,

    /// Returns the payload when this event has `tag`, otherwise `null`.
    pub fn get(self: Event, comptime tag: Tag) ?@FieldType(Event, @tagName(tag)) {
        switch (self) {
            tag => |v| return v,
            else => return null,
        }
    }
};

/// Identifies the ladder used to determine the destination level and arrival
/// position.
pub const ChangingLevel = struct {
    by_ladder: c.Ladder,
};

/// Describes a player movement so level and viewport state can be updated
/// after the position change has been applied.
pub const PlayerMoved = struct {
    /// The entity's position before the move.
    moved_from: p.Point,
    /// A direction relative to `moved_from`, or an absolute destination.
    target: g.actions.Action.Payload.Move.Target,

    /// Resolves `target` to the absolute destination cell.
    pub fn targetPlace(self: PlayerMoved) p.Point {
        return switch (self.target) {
            .direction => |direction| self.moved_from.movedTo(direction),
            .new_place => |place| place,
        };
    }
};

/// Requests a `GameSession` mode transition.
pub const ModeChanged = union(enum) {
    /// Return to level exploration.
    to_explore,
    /// Open the look-around mode.
    to_looking_around,
    /// Open the level-up mode.
    to_level_up,
    /// Open the inventory mode.
    to_inventory,
    /// Open the shop associated with this entity.
    to_trading: g.Entity,
    /// Open the modify/recognize mode.
    to_modify_recognize,
    /// Resume play, optionally restoring a target and performing a queued action.
    to_play: struct {
        /// An entity that should be targeted in focus; This is either the previous
        /// target or a new target from the `Explore` mode.
        entity_in_focus: ?g.Entity,

        /// An action to perform; Usually an action initiated during managing the inventory
        /// (eating or drinking as an example).
        action: ?g.actions.Action,
    },
};
