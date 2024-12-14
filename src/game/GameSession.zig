//! This is the root object for the single game session,
//! which contains the current level, all entities and components.
//! The GameSession has three modes: the `PlayMode`, `LookingAroundMode` and `ExploreMode`.
//! That modes are part of the GameSession extracted to the separate files to make their maintenance easier.
//! The `Mode` enum shows in which exactly mode the GameSession right now, but all implementations of the modes
//! are not union. Instead, they are permanent part of the GameSession. It makes memory management easier and effective,
//! because usually player switch between modes very often.
//! See their documentations for more details.

const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const PlayMode = @import("PlayMode.zig");
const ExploreMode = @import("ExploreMode.zig");
const LookingAroundMode = @import("LookingAroundMode.zig");

const log = std.log.scoped(.game_session);

const GameSession = @This();

pub const Mode = enum { play, explore, looking_around };

/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
/// The PRNG initialized by the session's seed. This prng is used to make any dynamic decision by AI, or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
runtime: g.Runtime,
render: *g.Render,
events: *g.events.EventBus,
level_arena: std.heap.ArenaAllocator,
/// The current mode of the game
mode: Mode = .play,
/// The current level
level: *g.Level = undefined,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,
looking_around: LookingAroundMode,

pub fn create(
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    runtime: g.Runtime,
    render: *g.Render,
    events: *g.events.EventBus,
) !*GameSession {
    const alloc = arena.allocator();
    log.debug("Begin the new game session with seed {d}", .{seed});
    const self = try alloc.create(GameSession);
    self.* = .{
        .seed = seed,
        .prng = std.Random.DefaultPrng.init(seed),
        .render = render,
        .runtime = runtime,
        .events = events,
        .level_arena = std.heap.ArenaAllocator.init(alloc),
        .play_mode = try PlayMode.init(self, alloc),
        .looking_around = try LookingAroundMode.init(self, alloc),
        .explore_mode = ExploreMode.init(self),
    };
    self.level = try g.Levels.firstLevel(&self.level_arena, g.entities.Player, true);
    log.debug("The first level has been created", .{});

    try events.subscribeOn(.entity_moved, self.play_mode.subscriber());
    try events.subscribeOn(.player_hit, self.play_mode.subscriber());

    render.viewport.region.top_left = .{ .row = 1, .col = 1 };
    try self.play_mode.update(null);
    return self;
}

pub fn unsubscribe(self: *GameSession) !void {
    try self.events.unsubscribe(&self.play_mode, .entity_moved);
    try self.events.unsubscribe(&self.play_mode, .player_hit);
}

pub fn movePlayerToLevel(self: *GameSession, by_ladder: c.Ladder) !void {
    const player = try self.level.components.entityToStruct(self.level.player);
    const new_depth: u8 = switch (by_ladder.direction) {
        .up => self.level.depth - 1,
        .down => self.level.depth + 1,
    };
    log.debug(
        \\
        \\--------------------
        \\Move {s} from the level {d} to {d}
        \\By the {any}
        \\--------------------
    ,
        .{ @tagName(by_ladder.direction), self.level.depth, new_depth, by_ladder },
    );

    // TODO persist the current level
    _ = self.level_arena.reset(.retain_capacity);
    self.play_mode.entity_in_focus = null;
    self.play_mode.quick_action = null;
    self.level = switch (new_depth) {
        0 => try g.Levels.firstLevel(&self.level_arena, player, false),
        1 => try g.Levels.cave(
            &self.level_arena,
            self.seed + new_depth,
            new_depth,
            player,
            by_ladder,
        ),
        else => try g.Levels.catacomb(
            &self.level_arena,
            self.seed + new_depth,
            new_depth,
            player,
            by_ladder,
        ),
    };
    self.render.viewport.centeredAround(self.level.playerPosition().point);
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode = .play;
    try self.play_mode.update(entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    self.mode = .explore;
    try self.explore_mode.refresh();
}

pub fn lookAround(self: *GameSession) !void {
    self.mode = .looking_around;
    try self.looking_around.refresh();
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.play_mode.tick(),
        .explore => try self.explore_mode.tick(),
        .looking_around => try self.looking_around.tick(),
    }
}
