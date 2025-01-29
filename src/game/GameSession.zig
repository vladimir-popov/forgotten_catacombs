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

pub const Mode = union(enum) {
    play: PlayMode,
    explore: ExploreMode,
    looking_around: LookingAroundMode,

    inline fn deinit(self: *Mode) void {
        switch (self.*) {
            .play => self.play.deinit(),
            .looking_around => self.looking_around.deinit(),
            .explore => {},
        }
    }
};

arena: *std.heap.ArenaAllocator,
/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
rand: std.Random,
runtime: g.Runtime,
render: *g.Render,
events: *g.events.EventBus,
/// The current level
level: *g.Level,
level_arena: std.heap.ArenaAllocator,
/// The current mode of the game
mode: Mode,

/// Create a new game session.
///
/// arena -   used to allocate any objects inside the game session.
///           Should be deinited at the end of life of this game session.
/// seed  -   Used to generate levels. Can be used for reproducing game session.
/// rand  -   Used to make decisions by AI, and to generate other game events,
///           such as damage and etc.
/// runtime - Particular runtime.
/// render  - Implementation of the render.
/// events  - EventBus used to handle events happened during the game session.
///
pub fn create(
    arena: *std.heap.ArenaAllocator,
    seed: u64,
    rand: std.Random,
    runtime: g.Runtime,
    render: *g.Render,
    events: *g.events.EventBus,
) !*GameSession {
    log.info("Begin the new game session with seed {d}", .{seed});
    defer log.info("The new game session with seed {d} has been created", .{seed});

    const alloc = arena.allocator();
    const self = try alloc.create(GameSession);
    self.* = .{
        .arena = arena,
        .seed = seed,
        .rand = rand,
        .render = render,
        .runtime = runtime,
        .events = events,
        .level_arena = std.heap.ArenaAllocator.init(alloc),
        .level = try g.Levels.firstLevel(&self.level_arena, g.entities.Player, true),
        .mode = .{ .play = try PlayMode.init(alloc, self, null) },
    };
    log.debug("The first level has been created", .{});

    try events.subscribe(self.subscriber());

    render.viewport.region.top_left = .{ .row = 1, .col = 1 };
    return self;
}

pub fn destroy(self: *g.GameSession) void {
    const alloc = self.arena.child_allocator;
    std.debug.assert(self.events.unsubscribe(self));
    self.arena.deinit();
    alloc.destroy(self.arena);
    alloc.destroy(self);
}

pub fn subscriber(self: *GameSession) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *GameSession = @ptrCast(@alignCast(ptr));
    switch (self.mode) {
        .play => try self.mode.play.handleEvent(event),
        else => {},
    }
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play = try PlayMode.init(self.arena.allocator(), self, entity_in_focus) };
    try self.mode.play.redraw();
}

pub fn explore(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .explore = ExploreMode.init(self) };
    try self.mode.explore.redraw();
}

pub fn lookAround(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .looking_around = try LookingAroundMode.init(self.arena.allocator(), self) };
    try self.mode.looking_around.redraw();
}

pub inline fn tick(self: *GameSession) !void {
    log.info("Tick {s}", .{@tagName(self.mode)});
    switch (self.mode) {
        .play => try self.mode.play.tick(),
        .explore => try self.mode.explore.tick(),
        .looking_around => try self.mode.looking_around.tick(),
    }
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
    try self.play(null);
}
