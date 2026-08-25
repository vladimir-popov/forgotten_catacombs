const std = @import("std");
const Type = std.builtin.Type;
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.events);

pub const Event = union(enum) {
    const Tag = @typeInfo(Event).@"union".tag_type.?;

    level_changed: ChangingLevel,
    entity_moved: EntityMoved,
    entity_died: g.Entity,
    mode_changed: ModeChanged,

    pub fn get(self: Event, comptime tag: Tag) ?@FieldType(Event, @tagName(tag)) {
        switch (self) {
            tag => |v| return v,
            else => return null,
        }
    }
};

pub const ChangingLevel = struct {
    by_ladder: c.Ladder,
};

pub const EntityMoved = struct {
    entity: g.Entity,
    is_player: bool,
    moved_from: p.Point,
    target: g.actions.Action.Payload.Move.Target,

    pub fn targetPlace(self: EntityMoved) p.Point {
        return switch (self.target) {
            .direction => |direction| self.moved_from.movedTo(direction),
            .new_place => |place| place,
        };
    }
};

/// The mode of the GameSession should be changed on handling this event.
pub const ModeChanged = union(enum) {
    to_explore,
    to_looking_around,
    to_level_up,
    to_inventory,
    to_trading: g.Entity,
    to_modify_recognize,
    to_play: struct {
        /// An entity that should be targeted in focus; This is either the previous
        /// target or a new target from the `Explore` mode.
        entity_in_focus: ?g.Entity,

        /// An action to perform; Usually an action initiated during managing the inventory
        /// (eating or drinking as an example).
        action: ?g.actions.Action,
    },
};
