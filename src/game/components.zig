const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

pub const Position = struct {
    point: p.Point,
};

pub const Door = struct { state: enum { opened, closed } };

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: g.Codepoint,
    /// The sprite with bigger order should be rendered over the sprite with lower
    z_order: u2,
};

pub const Description = struct {
    name: []const u8,
    description: []const u8 = "",
};

pub const Animation = struct {
    pub const Presets = struct {
        pub const hit: [3]g.Codepoint = [_]g.Codepoint{ 0, 'X', 0 };
        pub const miss: [1]g.Codepoint = [_]g.Codepoint{'.'};
    };

    /// Frames of the animation. One frame per render circle will be shown.
    frames: []const g.Codepoint,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    lag: u32 = 0,

    pub fn frame(self: *Animation, now: c_uint) ?g.Codepoint {
        self.lag += now - self.previous_render_time;
        self.previous_render_time = now;
        if (self.lag > g.RENDER_DELAY_MS) {
            self.lag = 0;
            self.current_frame += 1;
        }
        return if (self.current_frame <= self.frames.len) self.frames[self.current_frame - 1] else null;
    }
};

/// The ladder to the upper or under level from the current one
pub const Ladder = struct {
    pub const Direction = enum { up, down };
    /// Direction of the ladder
    direction: Direction,
    /// The id of the ladder on this level.
    this_ladder: g.Entity,
    /// The id of the ladder on that level.
    that_ladder: ?g.Entity,
};

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = struct {
    pub const Move = struct {
        pub const Target = union(enum) {
            new_place: p.Point,
            direction: p.Direction,
        };
        target: Target,
        keep_moving: bool = false,
    };
    pub const Type = union(enum) {
        /// Skip the round
        wait,
        /// An entity is going to move in the direction
        move: Move,
        /// An entity is going to open a door
        open: g.Entity,
        /// An entity is going to close a door
        close: g.Entity,
        /// An entity which should be hit
        hit: g.Entity,
        /// An entity is going to take the item
        take: g.Entity,
        /// The player moves from the level to another level
        move_to_level: Ladder,
    };

    type: Type,

    move_points: u8,
};

/// Intersection of two objects
pub const Collision = struct {
    pub const Obstacle = union(enum) {
        wall,
        closed_door: g.Entity,
        item: g.Entity,
        enemy: g.Entity,
    };

    /// Who met obstacle
    entity: g.Entity,
    /// With what exactly collision happened
    obstacle: Obstacle,
    /// Where the collision happened
    at: p.Point,
};

pub const Health = struct {
    // The count of maximum hp
    max: u8,
    // The count of the current hp
    current: i16,
};

/// This is only **intension** to make a damage.
/// The real damage will be counted in the DamageSystem
pub const Damage = struct {
    /// Damage amount
    amount: u8,
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: u8 = 10,
};

pub const MeleeWeapon = struct {
    max_damage: u8,
    move_points: u8,

    pub fn damage(self: MeleeWeapon, rand: std.Random) Damage {
        return .{ .amount = rand.uintLessThan(u8, self.max_damage) + 1 };
    }
};

pub const NPC = struct {
    pub const Type = enum { melee };

    type: Type = .melee,
};

pub const Components = struct {
    animation: ?Animation = null,
    collision: ?Collision = null,
    damage: ?Damage = null,
    description: ?Description = null,
    door: ?Door = null,
    health: ?Health = null,
    ladder: ?Ladder = null,
    melee_weapon: ?MeleeWeapon = null,
    move: ?Action = null,
    npc: ?NPC = null,
    position: ?Position = null,
    speed: ?Speed = null,
    sprite: ?Sprite = null,
};
