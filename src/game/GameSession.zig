//! This is the root object for the single game session,
//! which contains the current level, all entities and components.
//! The GameSession has three modes: the `PlayMode`, `LookingAroundMode` and `ExploreMode`.
//! That modes are part of the GameSession extracted to the separate files to make their maintenance easier.

const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const PlayMode = @import("PlayMode.zig");
const ExploreMode = @import("ExploreMode.zig");
const LookingAroundMode = @import("LookingAroundMode.zig");

const log = std.log.scoped(.game_session);

const Events = std.ArrayListUnmanaged(Event);

pub const Event = union(enum) {
    const Tag = @typeInfo(Event).Union.tag_type.?;

    entity_moved: EntityMoved,
    entity_died: EntityDied,
    player_hit: PlayerHit,

    pub fn get(self: Event, comptime tag: Tag) ?std.meta.TagPayload(Event, tag) {
        switch (self) {
            tag => |v| return v,
            else => return null,
        }
    }
};

pub const EntityMoved = struct {
    entity: g.Entity,
    is_player: bool,
    moved_from: p.Point,
    target: g.Action.Move.Target,

    pub fn targetPlace(self: EntityMoved) p.Point {
        return switch (self.target) {
            .direction => |direction| self.moved_from.movedTo(direction),
            .new_place => |place| place,
        };
    }
};

pub const EntityDied = struct {
    entity: g.Entity,
    is_player: bool,
};

pub const PlayerHit = struct { target: g.Entity };

const GameSession = @This();

pub const Mode = union(enum) {
    pub const Tag = @typeInfo(Mode).Union.tag_type.?;

    play_mode: PlayMode,
    explore_mode: ExploreMode,
    looking_around_mode: LookingAroundMode,

    inline fn deinit(self: *Mode) void {
        switch (self.*) {
            .play_mode => self.play_mode.deinit(),
            .looking_around_mode => self.looking_around_mode.deinit(),
            .explore_mode => {},
        }
    }
};

alloc: std.mem.Allocator,
/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
rand: std.Random,
runtime: g.Runtime,
render: *g.Render,
ai: g.AI,
/// Set of events happened during the one tick
events: Events,
/// The current level
level: *g.Level,
level_arena: std.heap.ArenaAllocator,
/// The current mode of the game
mode: Mode,

/// Initializes a new game session.
///
/// seed  -   Used to generate levels. Can be used for reproducing game session.
/// rand  -   Used to make decisions by AI, and to generate other game events,
///           such as damage and etc.
/// runtime - Particular runtime.
/// render  - Implementation of the render.
///
pub fn create(
    alloc: std.mem.Allocator,
    seed: u64,
    rand: std.Random,
    runtime: g.Runtime,
    render: *g.Render,
) !*GameSession {
    log.info("Begin the new game session with seed {d}", .{seed});

    render.viewport.region.top_left = .{ .row = 1, .col = 1 };
    const self = try alloc.create(g.GameSession);
    self.* = .{
        .alloc = alloc,
        .seed = seed,
        .rand = rand,
        .render = render,
        .runtime = runtime,
        .events = try Events.initCapacity(alloc, 5),
        .level_arena = std.heap.ArenaAllocator.init(alloc),
        .level = try g.Levels.firstLevel(&self.level_arena, g.entities.Player, true),
        .ai = g.AI{ .rand = rand },
        .mode = .{ .play_mode = PlayMode.init(self) },
    };
    try self.mode.play_mode.update(null);
    return self;
}

pub fn destroy(self: *g.GameSession) void {
    self.events.deinit(self.alloc);
    self.level_arena.deinit();
    self.mode.deinit();
    self.alloc.destroy(self);
}

pub fn sendEvent(self: *g.GameSession, event: Event) !void {
    log.debug("Event happened: {any}", .{event});
    try self.events.append(self.alloc, event);
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play_mode = PlayMode.init(self) };
    try self.mode.play_mode.update(entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .explore_mode = ExploreMode.init(self) };
    try self.mode.explore_mode.update();
}

pub fn lookAround(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .looking_around_mode = try LookingAroundMode.init(self) };
    try self.mode.looking_around_mode.redraw();
}

/// Returns true only when player is dead
pub inline fn tick(self: *GameSession) !g.Game.TickResult {
    log.info("Tick {s}", .{@tagName(self.mode)});
    defer self.events.clearRetainingCapacity();

    switch (self.mode) {
        .explore_mode => try self.mode.explore_mode.tick(),
        .looking_around_mode => try self.mode.looking_around_mode.tick(),
        .play_mode => switch (try self.mode.play_mode.tick()) {
            .play_mode => { // handle events:
                for (self.events.items) |event| {
                    switch (event) {
                        .entity_died => |entity_died| {
                            if (entity_died.is_player) {
                                return .player_dead;
                            }
                        },
                        .entity_moved => |entity_moved| {
                            if (entity_moved.is_player)
                                try self.render.viewport.keepPlayerInView(entity_moved);
                        },
                        else => {},
                    }
                    try self.mode.play_mode.handleEvent(event);
                    log.debug("Event handled: {any}", .{event});
                }
            },
            .looking_around_mode => try self.lookAround(),
            .explore_mode => try self.explore(),
        },
    }
    return .continue_game;
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
