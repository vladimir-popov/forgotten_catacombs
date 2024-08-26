const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const gm = @import("game.zig");
const dung = @import("BspDungeon.zig");

// coz zig uses u21 for utf8 symbols
pub const Codepoint = u21;

pub const Position = struct {
    point: p.Point,

    pub fn deinit(_: *@This()) void {}
};

/// Describes how and where something should look.
pub const Sprite = struct {
    codepoint: Codepoint,
    /// The sprite with bigger order should be rendered over the sprite with lower
    z_order: u2 = 0,
    pub fn deinit(_: *@This()) void {}
};

pub const Description = struct {
    name: []const u8,
    description: []const u8 = "",

    pub fn deinit(_: *@This()) void {}
};

pub const Animation = struct {
    pub const Presets = struct {
        pub const hit: [3]Codepoint = [_]Codepoint{ 0, 'X', 0 };
        pub const miss: [1]Codepoint = [_]Codepoint{'.'};
    };

    /// Frames of the animation. One frame per render circle will be shown.
    frames: []const Codepoint,
    current_frame: u8 = 0,
    previous_render_time: c_uint = 0,
    lag: u32 = 0,

    pub fn frame(self: *Animation, now: c_uint) ?Codepoint {
        self.lag += now - self.previous_render_time;
        self.previous_render_time = now;
        if (self.lag > gm.RENDER_DELAY_MS) {
            self.lag = 0;
            self.current_frame += 1;
        }
        return if (self.current_frame <= self.frames.len) self.frames[self.current_frame - 1] else null;
    }

    pub fn deinit(_: *@This()) void {}
};

pub const Door = enum {
    opened,
    closed,
    pub fn deinit(_: *@This()) void {}
};

/// The ladder to the upper or under level from the current one
pub const Ladder = struct {
    pub const Direction = enum { up, down };
    /// Direction of the ladder
    direction: Direction,
    /// The id of the ladder on this level.
    this_ladder: gm.Entity,
    /// The id of the ladder on that level.
    that_ladder: ?gm.Entity,
    pub fn deinit(_: *@This()) void {}
};

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = struct {
    pub const Move = struct {
        direction: p.Direction,
        keep_moving: bool = false,
    };
    pub const Type = union(enum) {
        /// Skip the round
        wait,
        /// An entity is going to move in the direction
        move: Move,
        /// An entity is going to open a door
        open: gm.Entity,
        /// An entity is going to close a door
        close: gm.Entity,
        /// An entity which should be hit
        hit: gm.Entity,
        /// An entity is going to take the item
        take: gm.Entity,
        /// The player moves from the level to another level
        move_to_level: Ladder,
    };

    type: Type,

    move_points: u8,

    pub fn deinit(_: *@This()) void {}
};

/// Intersection of two objects
pub const Collision = struct {
    pub const Obstacle = union(enum) {
        wall,
        door: struct { entity: gm.Entity, state: gm.Door },
        item: gm.Entity,
        enemy: gm.Entity,
    };

    /// Who met obstacle
    entity: gm.Entity,
    /// With what exactly collision happened
    obstacle: Obstacle,
    /// Where the collision happened
    at: p.Point,

    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    // The count of maximum hp
    max: u8,
    // The count of the current hp
    current: i16,
    pub fn deinit(_: *@This()) void {}
};

/// This is only **intension** to make a damage.
/// The real damage will be counted in the DamageSystem
pub const Damage = struct {
    /// Damage amount
    amount: u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Speed = struct {
    /// How many move points are needed for moving on the neighbor position
    move_points: u8 = 10,

    pub fn deinit(_: *@This()) void {}
};

pub const MeleeWeapon = struct {
    max_damage: u8,
    move_points: u8,

    pub fn damage(self: MeleeWeapon, rand: std.Random) Damage {
        return .{ .amount = rand.uintLessThan(u8, self.max_damage) + 1 };
    }

    pub fn deinit(_: *@This()) void {}
};

pub const NPC = struct {
    pub const Type = enum { melee };

    type: Type = .melee,

    pub fn deinit(_: *@This()) void {}
};

pub const Components = union {
    position: Position,
    sprite: Sprite,
    door: Door,
    ladder: Ladder,
    animation: Animation,
    move: Action,
    description: Description,
    health: Health,
    damage: Damage,
    collision: Collision,
    speed: Speed,
    melee: MeleeWeapon,
    npc: NPC,
};
