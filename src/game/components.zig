const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const dung = @import("BspDungeon.zig");

pub const Codepoint = u21;

/// Describes how and where something should look.
pub const Sprite = struct {
    // The sprite and position are merged together for better performance
    position: p.Point,
    codepoint: Codepoint,
    pub fn deinit(_: *@This()) void {}
};

pub const Animation = struct {
    pub const Presets = struct {
        pub const hit: [1]Codepoint = [_]Codepoint{'*'};
        pub const miss: [1]Codepoint = [_]Codepoint{'.'};
    };

    /// Frames of the animation. One frame per render circle will be shown.
    frames: []const Codepoint,
    /// Where the animation should be played
    position: p.Point,

    pub fn deinit(_: *@This()) void {}
};

/// The intension to perform an action.
/// Describes what some entity is going to do.
pub const Action = union(enum) {
    pub const Move = struct {
        direction: p.Direction,
        keep_moving: bool = false,
    };

    /// Skip the round
    wait,
    /// An entity is going to open a door at some place
    open: p.Point,
    /// An entity is going to close a door at some place
    close: p.Point,
    /// An entity is going to move in the direction
    move: Move,
    /// An entity is going to hit the enemy
    hit: game.Entity,
    /// An entity is going to take the item
    take: game.Entity,

    pub fn deinit(_: *@This()) void {}
};

/// Intersection of two objects
pub const Collision = struct {
    pub const Obstacle = union(enum) {
        opened_door,
        closed_door,
        wall,
        entity: game.Entity,
    };

    /// Who met obstacle
    entity: game.Entity,
    /// With what exactly collision happened
    obstacle: Obstacle,
    /// Where the collision happened
    at: p.Point,

    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    hp: i16,
    pub fn deinit(_: *@This()) void {}
};

/// This is only **intension** to make a damage.
/// The real damage will be counted in the DamageSystem
pub const Damage = struct {
    /// Who should be harmed
    entity: game.Entity,
    /// Damage amount
    amount: u8,
    pub fn deinit(_: *@This()) void {}
};

pub const Description = struct {
    name: []const u8,
    description: []const u8 = "",

    pub fn deinit(_: *@This()) void {}
};

pub const Components = union {
    sprite: Sprite,
    animation: Animation,
    move: Action,
    description: Description,
    health: Health,
    damage: Damage,
    collision: Collision,
};
