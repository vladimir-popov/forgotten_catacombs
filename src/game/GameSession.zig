//! This is the root object for the game session,
//! which contains all entities, components, modes, and current runtime
//! implementation.

const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const game = @import("game.zig");

const PlayMode = @import("PlayMode.zig");
const ExploreMode = @import("ExploreMode.zig");

const log = std.log.scoped(.GameSession);

const GameSession = @This();

const Mode = enum { play, explore };

/// The root object of the game
game: *game.Game,
/// Collection of the entities of this game session
entities: ecs.EntitiesManager,
/// Collection of the components of the entities
components: ecs.ComponentsManager(game.Components),
/// Aggregates requests of few components for the same entities at once
query: ecs.ComponentsQuery(game.Components) = undefined,
/// Visible area
screen: game.Screen,
/// The pointer to the current dungeon
dungeon: *game.Dungeon,
/// Entity of the player
player: game.Entity = undefined,
/// The current mode of the game
mode: Mode = .play,
// stateful modes:
play_mode: PlayMode = undefined,
explore_mode: ExploreMode = undefined,

pub fn create(gm: *game.Game) !*GameSession {
    const session = try gm.runtime.alloc.create(GameSession);
    session.* = .{
        .game = gm,
        .screen = game.Screen.init(game.DISPLAY_ROWS - 1, game.DISPLAY_COLS, game.Dungeon.Region),
        .entities = try ecs.EntitiesManager.init(gm.runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(gm.runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(gm.runtime.alloc, gm.runtime.rand),
    };
    session.query = .{ .entities = &session.entities, .components = &session.components };
    const player_and_position = try initLevel(session.dungeon, &session.entities, &session.components);
    session.player = player_and_position[0];
    session.screen.centeredAround(player_and_position[1]);
    session.play_mode = try PlayMode.init(session);
    session.explore_mode = try ExploreMode.init(session);
    try session.play(null);
    return session;
}

pub fn destroy(self: *GameSession) void {
    self.entities.deinit();
    self.components.deinit();
    self.dungeon.destroy();
    self.play_mode.deinit();
    self.explore_mode.deinit();
    self.game.runtime.alloc.destroy(self);
}

pub fn play(self: *GameSession, entity_in_focus: ?game.Entity) !void {
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

pub fn entityAt(session: *game.GameSession, place: p.Point) ?game.Entity {
    for (session.components.arrayOf(game.Position).components.items, 0..) |position, idx| {
        if (position.point.eql(place)) {
            return session.components.arrayOf(game.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

pub fn removeEntity(self: *GameSession, entity: game.Entity) !void {
    try self.components.removeAllForEntity(entity);
    self.entities.removeEntity(entity);
}

// this is public to reuse in the DungeonsGenerator
pub fn initLevel(
    dungeon: *game.Dungeon,
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
) !struct { game.Entity, p.Point } {
    var doors = dungeon.doors.keyIterator();
    while (doors.next()) |at| {
        try addClosedDoor(entities, components, at);
    }

    const player_position = randomEmptyPlace(dungeon, components) orelse unreachable;
    const player = try initPlayer(entities, components, player_position);
    for (0..dungeon.rand.uintLessThan(u8, 10) + 10) |_| {
        try addRat(dungeon, entities, components);
    }

    return .{ player, player_position };
}

fn addClosedDoor(
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
    door_at: *p.Point,
) !void {
    const door = try entities.newEntity();
    try components.setToEntity(door, game.Door.closed);
    try components.setToEntity(door, game.Position{ .point = door_at.* });
    try components.setToEntity(door, game.Sprite{ .codepoint = '+' });
    try components.setToEntity(door, game.Description{ .name = "Door" });
}

fn initPlayer(
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
    init_position: p.Point,
) !game.Entity {
    const player = try entities.newEntity();
    try components.setToEntity(player, game.Position{ .point = init_position });
    try components.setToEntity(player, game.Sprite{ .codepoint = '@', .z_order = 3 });
    try components.setToEntity(player, game.Description{ .name = "You" });
    try components.setToEntity(player, game.Health{ .max = 100, .current = 30 });
    try components.setToEntity(player, game.MeleeWeapon{ .max_damage = 3, .move_points = 10 });
    try components.setToEntity(player, game.Speed{ .move_points = 10 });
    return player;
}

fn addRat(
    dungeon: *game.Dungeon,
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
) !void {
    if (randomEmptyPlace(dungeon, components)) |position| {
        const rat = try entities.newEntity();
        try components.setToEntity(rat, game.NPC{ .type = .melee });
        try components.setToEntity(rat, game.Position{ .point = position });
        try components.setToEntity(rat, game.Sprite{ .codepoint = 'r', .z_order = 3 });
        try components.setToEntity(rat, game.Description{ .name = "Rat" });
        try components.setToEntity(rat, game.Health{ .max = 10, .current = 10 });
        try components.setToEntity(rat, game.MeleeWeapon{ .max_damage = 3, .move_points = 5 });
        try components.setToEntity(rat, game.Speed{ .move_points = 10 });
    }
}

fn randomEmptyPlace(dungeon: *game.Dungeon, components: *const ecs.ComponentsManager(game.Components)) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = dungeon.randomPlace();
        var is_empty = true;
        for (components.getAll(game.Position)) |position| {
            if (position.point.eql(place)) {
                is_empty = false;
            }
        }
        if (is_empty) return place;
    }
    return null;
}
