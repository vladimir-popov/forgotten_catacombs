//! This is the root object for the single game session,
//! which contains the current level, all entities and components, and pointer to the
//! Game object.
//! The GameSession has two modes: the `PlayMode` and `ExploreMode`. See their documentations
//! for more details.

const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const gm = @import("game.zig");

const PlayMode = @import("PlayMode.zig");
const ExploreMode = @import("ExploreMode.zig");

const log = std.log.scoped(.GameSession);

const GameSession = @This();

const Mode = enum { play, explore };

/// The root object of the game
game: *gm.Game,
/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
/// The PRNG initialized by the session's seed. This prng is used to make any dynamic decision by AI, or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
/// The current level
level: gm.Level,
/// Collection of the components of the entities
components: ecs.ComponentsManager(gm.Components),
/// The current mode of the game
mode: Mode,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,
/// Id for the next generate entity
next_entity: gm.Entity = 0,
/// Entity of the player
player: gm.Entity = undefined,

pub fn createNew(game: *gm.Game, seed: u64) !*GameSession {
    log.debug("Begin the new game session with seed {d}", .{seed});
    const session = try game.runtime.alloc.create(GameSession);
    session.* = .{
        .game = game,
        .seed = seed,
        .prng = std.Random.DefaultPrng.init(seed),
        .components = try ecs.ComponentsManager(gm.Components).init(game.runtime.alloc),
        .mode = .play,
        .play_mode = try PlayMode.init(session),
        .explore_mode = try ExploreMode.init(session),
        .level = undefined,
    };
    session.player = try session.newEntity();
    session.level = try gm.Level.generate(session, 0);
    return session;
}

pub fn destroy(self: *GameSession) void {
    self.components.deinit();
    self.level.deinit();
    self.play_mode.deinit();
    self.explore_mode.deinit();
    self.game.runtime.alloc.destroy(self);
}

// TODO: Load session from file

/// Generates an unique id for the new entity.
/// The id is unique for whole life circle of this session.
pub fn newEntity(self: *GameSession) !gm.Entity {
    const entity = self.next_entity;
    self.next_entity += 1;
    return entity;
}

pub fn playerPosition(self: *const GameSession) p.Point {
    return self.components.getForEntityUnsafe(self.player, gm.Position).point;
}

pub fn play(self: *GameSession, entity_in_focus: ?gm.Entity) !void {
    self.mode = .play;
    try self.play_mode.refresh(entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    self.mode = .explore;
    try self.explore_mode.refresh();
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.play_mode.tick(),
        .explore => try self.explore_mode.tick(),
    }
}
