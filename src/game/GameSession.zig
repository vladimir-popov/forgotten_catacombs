//! This is the root object for the single game session,
//! which contains the current level, all entities and components, and pointer to the
//! Game object.
//! The GameSession has two modes: the `PlayMode` and `ExploreMode`. See their documentations
//! for more details.

const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const PlayMode = @import("PlayMode.zig");
const ExploreMode = @import("ExploreMode.zig");

const log = std.log.scoped(.GameSession);

const GameSession = @This();

const Mode = enum { play, explore };

/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
/// The PRNG initialized by the session's seed. This prng is used to make any dynamic decision by AI, or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
render: g.Render,
/// Visible area
viewport: g.Viewport,
runtime: g.Runtime,
events: *g.events.EventBus,
/// The current level
level: g.Level = undefined,
level_arena: std.heap.ArenaAllocator,
/// The current mode of the game
mode: Mode = .play,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,

pub fn initNew(
    self: *GameSession,
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    runtime: g.Runtime,
    render: g.Render,
    events: *g.events.EventBus,
) !void {
    log.debug("Begin the new game session with the seed {d}", .{seed});
    self.* = .{
        .seed = seed,
        .prng = std.Random.DefaultPrng.init(seed),
        .render = render,
        .viewport = try g.Viewport.init(arena.allocator(), g.DISPLAY_ROWS - 2, g.DISPLAY_COLS),
        .runtime = runtime,
        .events = events,
        .level_arena = std.heap.ArenaAllocator.init(arena.allocator()),
        .play_mode = try PlayMode.init(self, arena.allocator()),
        .explore_mode = try ExploreMode.init(self, arena.allocator()),
    };
    try events.subscribeOn(.entity_moved, self.viewport.subscriber());
    try events.subscribeOn(.entity_moved, self.level.subscriber());
    try events.subscribeOn(.player_hit, self.play_mode.subscriber());

    const entrance = 0;
    try self.level.generate(
        self.level_arena.allocator(),
        seed,
        0,
        g.entities.Player,
        entrance,
        null,
        .down,
    );
    try self.level.movePlayerToLadder(entrance);
    self.viewport.centeredAround(self.level.playerPosition().point);
}

pub fn moveToLevel(self: *GameSession, ladder: c.Ladder) !void {
    const player = try self.level.components.entityToStruct(self.level.player);
    // TODO persist the current level
    _ = self.level_arena.reset(.retain_capacity);

    var this_ladder: g.Entity = undefined;
    var that_ladder: ?g.Entity = undefined;
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
        "\n--------------------\nMove {s} from the level {d} to {d}\n--------------------",
        .{ @tagName(ladder.direction), self.level.depth, new_depth },
    );
    try self.level.generate(
        self.level_arena.allocator(),
        self.seed + new_depth,
        new_depth,
        player,
        this_ladder,
        that_ladder,
        ladder.direction,
    );
    try self.level.movePlayerToLadder(this_ladder);
    self.viewport.centeredAround(self.level.playerPosition().point);
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
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
