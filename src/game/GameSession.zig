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
/// The current mode of the game
mode: Mode,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,
/// Generate id for new entities.
/// The ids should be unique for whole life circle of this session.
entities_provider: ecs.EntitiesProvider,
/// Entity of the player
player: gm.Entity = undefined,

pub fn createNew(game: *gm.Game, seed: u64) !*GameSession {
    log.debug("Begin the new game session with seed {d}", .{seed});
    const session = try game.runtime.alloc.create(GameSession);
    session.* = .{
        .game = game,
        .seed = seed,
        .prng = std.Random.DefaultPrng.init(seed),
        .entities_provider = .{},
        .mode = .play,
        .play_mode = try PlayMode.init(session),
        .explore_mode = try ExploreMode.init(session),
        .level = undefined,
    };
    session.player = session.newEntity();
    log.debug("Player entity is {d}", .{session.player});
    const entrance = session.newEntity();
    session.level = try gm.Level.generate(
        game.runtime.alloc,
        seed,
        session.player,
        session.entities_provider,
        0,
        entrance,
        null,
        .down,
    );
    try session.level.movePlayerToLadder(entrance);
    session.game.render.screen.centeredAround(session.level.playerPosition().point);
    return session;
}

pub fn destroy(self: *GameSession) void {
    self.level.deinit();
    self.play_mode.deinit();
    self.explore_mode.deinit();
    self.game.runtime.alloc.destroy(self);
}

inline fn newEntity(self: *GameSession) gm.Entity {
    return self.entities_provider.newEntity();
}

// TODO: Load session from file

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

pub fn moveToLevel(self: *GameSession, ladder: gm.Ladder) !void {
    var this_ladder: gm.Entity = undefined;
    var that_ladder: ?gm.Entity = undefined;
    var new_depth: u8 = undefined;
    switch (ladder.direction) {
        .up => {
            this_ladder = ladder.that_ladder orelse
                std.debug.panic("Attempt to move up from the level {d}", .{self.level.depth});
            that_ladder = ladder.this_ladder;
            new_depth = self.level.depth - 1;
        },
        .down => {
            this_ladder = ladder.this_ladder;
            that_ladder = ladder.that_ladder;
            new_depth = self.level.depth + 1;
        },
    }
    std.log.debug(
        "Move {s} from the level {d} to {d}\n--------------------",
        .{ @tagName(ladder.direction), self.level.depth, new_depth },
    );
    var new_level = try gm.Level.generate(
        self.game.runtime.alloc,
        self.seed,
        self.player,
        self.entities_provider,
        new_depth,
        this_ladder,
        that_ladder,
        ladder.direction,
    );
    try self.level.components.moveAllForEntity(self.player, &new_level.components);
    self.level.deinit();
    self.level = new_level;
    try self.level.movePlayerToLadder(this_ladder);
    self.game.render.screen.centeredAround(self.level.playerPosition().point);
}
