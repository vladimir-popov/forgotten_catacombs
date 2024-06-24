const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const dung = @import("BspDungeon.zig");

pub const Codepoint = u21;

pub const Sprite = struct {
    position: p.Point,
    codepoint: Codepoint,
    pub fn deinit(_: *@This()) void {}
};

pub const Animation = struct {
    pub const Presets = struct {
        pub const hit: [1]Codepoint = [_]Codepoint{'*'};
        pub const miss: [1]Codepoint = [_]Codepoint{'.'};
    };

    frames: []const Codepoint,
    position: p.Point,

    pub fn deinit(_: *@This()) void {}
};

pub const Action = union(enum) {
    pub const Move = struct {
        direction: p.Direction,
        keep_moving: bool = false,
    };

    open: p.Point,
    close: p.Point,
    move: Move,
    hit: game.Entity,
    take: game.Entity,

    pub fn deinit(_: *@This()) void {}
};

pub const Collision = struct {
    pub const Obstacle = union(enum) {
        opened_door,
        closed_door,
        wall,
        entity: game.Entity,
    };

    /// Who met obstacle
    entity: game.Entity,
    obstacle: Obstacle,
    at: p.Point,

    pub fn deinit(_: *@This()) void {}
};

pub const Health = struct {
    hp: i16,
    pub fn deinit(_: *@This()) void {}
};

pub const Damage = struct {
    /// Who was harmed
    entity: game.Entity,
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
