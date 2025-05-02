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

arena: std.heap.ArenaAllocator,
/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
/// The PRNG initialized by the session's seed. This prng is used to make any dynamic decision by AI, or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
runtime: g.Runtime,
/// Buffered render to draw the game
render: g.Render,
/// Visible area
viewport: g.Viewport,
///
events: g.events.EventBus,
/// The current level
level: g.Level,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,
looking_around: LookingAroundMode,
/// The current mode of the game
mode: Mode,
is_game_over: bool,

pub fn init(
    self: *GameSession,
    gpa: std.mem.Allocator,
    seed: u64,
    runtime: g.Runtime,
    render: g.Render,
) !void {
    log.debug("Begin the new game session with seed {d}", .{seed});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .seed = seed,
        .prng = std.Random.DefaultPrng.init(seed),
        .runtime = runtime,
        .render = render,
        .viewport = g.Viewport.init(render.scene_rows, render.scene_cols),
        .events = g.events.EventBus.init(&self.arena),
        .level = undefined,
        .play_mode = try PlayMode.init(&self.arena, self, self.prng.random()),
        .looking_around = try LookingAroundMode.init(self.arena.allocator(), self),
        .explore_mode = ExploreMode.init(self),
        .mode = .play,
        .is_game_over = false,
    };
    try g.Levels.firstLevel(&self.level, self.arena.allocator(), g.entities.Player, true);
    try self.events.subscribe(self.play_mode.subscriber());
    try self.events.subscribe(self.viewport.subscriber());
    self.viewport.region.top_left = .{ .row = 1, .col = 1 };
    try self.play_mode.update(null);
}

pub fn deinit(self: *GameSession) void {
    self.arena.deinit();
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode = .play;
    try self.play_mode.update(entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    self.mode = .explore;
    try self.explore_mode.update();
}

pub fn lookAround(self: *GameSession) !void {
    self.mode = .looking_around;
    try self.looking_around.update();
}

pub fn subscriber(self: *GameSession) g.events.Subscriber {
    return .{ .context = self, .onEvent = gameOver };
}

pub fn gameOver(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *GameSession = @ptrCast(@alignCast(ptr));
    if (event == .entity_died and event.entity_died.is_player) {
        self.is_game_over = true;
    }
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.play_mode.tick(),
        .explore => try self.explore_mode.tick(),
        .looking_around => try self.looking_around.tick(),
    }
    try self.events.notifySubscribers();
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
    self.level.deinit();
    switch (new_depth) {
        0 => try g.Levels.firstLevel(&self.level, self.arena.allocator(), player, false),
        1 => try g.Levels.cave(
            &self.level,
            self.arena.allocator(),
            self.seed + new_depth,
            new_depth,
            player,
            by_ladder,
        ),
        else => try g.Levels.catacomb(
            &self.level,
            self.arena.allocator(),
            self.seed + new_depth,
            new_depth,
            player,
            by_ladder,
        ),
    }
    try self.play_mode.updateQuickActions(null);
    self.viewport.centeredAround(self.level.playerPosition().point);
}
