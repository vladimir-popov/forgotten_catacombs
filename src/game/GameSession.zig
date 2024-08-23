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
/// The current level
level: gm.Level,
/// Collection of the entities of this game session
entities: ecs.EntitiesManager,
/// Collection of the components of the entities
components: ecs.ComponentsManager(gm.Components),
/// Aggregates requests of few components for the same entities at once
query: ecs.ComponentsQuery(gm.Components),
/// Entity of the player
player: gm.Entity = undefined,
/// The current mode of the game
mode: Mode,
// stateful modes:
play_mode: PlayMode,
explore_mode: ExploreMode,

pub fn create(game: *gm.Game) !*GameSession {
    const session = try game.runtime.alloc.create(GameSession);
    session.* = .{
        .game = game,
        .entities = try ecs.EntitiesManager.init(game.runtime.alloc),
        .components = try ecs.ComponentsManager(gm.Components).init(game.runtime.alloc),
        .query = undefined,
        .mode = .play,
        .play_mode = try PlayMode.init(session),
        .explore_mode = try ExploreMode.init(session),
        .level = try gm.Level.init(session),
    };
    session.query = .{ .entities = &session.entities, .components = &session.components };
    return session;
}

pub fn destroy(self: *GameSession) void {
    self.entities.deinit();
    self.components.deinit();
    self.level.deinit();
    self.play_mode.deinit();
    self.explore_mode.deinit();
    self.game.runtime.alloc.destroy(self);
}

pub fn beginNew(self: *GameSession) !void {
    try self.initPlayer();
    try self.level.generate();
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?gm.Entity) !void {
    self.mode = .play;
    try self.play_mode.refresh(entity_in_focus);
}

pub fn pause(self: *GameSession) !void {
    self.mode = .explore;
    try self.explore_mode.refresh();
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.play_mode.tick(),
        .explore => try self.explore_mode.tick(),
    }
}

pub fn playerPosition(self: *const GameSession) p.Point {
    return self.components.getForEntityUnsafe(self.player, gm.Position).point;
}

fn initPlayer(self: *GameSession) !void {
    self.player = try self.entities.newEntity();
    try self.components.setToEntity(self.player, gm.Sprite{ .codepoint = '@', .z_order = 3 });
    try self.components.setToEntity(self.player, gm.Description{ .name = "You" });
    try self.components.setToEntity(self.player, gm.Health{ .max = 100, .current = 30 });
    try self.components.setToEntity(self.player, gm.MeleeWeapon{ .max_damage = 3, .move_points = 10 });
    try self.components.setToEntity(self.player, gm.Speed{ .move_points = 10 });
}
