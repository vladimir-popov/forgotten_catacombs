const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const game = @import("game.zig");

const Render = @import("Render.zig");

const log = std.log.scoped(.GameSession);

const Self = @This();

const Mode = union(enum) {
    play: game.PlayMode,
    pause: game.PauseMode,

    fn deinit(mode: *Mode) void {
        switch (mode.*) {
            .pause => |*pause_mode| pause_mode.deinit(),
            else => {},
        }
    }

    fn handleInput(mode: *Mode, buttons: game.Buttons) !void {
        switch (mode.*) {
            .play => |play_mode| try play_mode.handleInput(buttons),
            .pause => |*pause_mode| try pause_mode.handleInput(buttons),
        }
    }

    fn runSystems(mode: *Mode) !void {
        return switch (mode.*) {
            .play => |*play_mode| {
                for (play_mode.systems) |sys| {
                    try sys(play_mode);
                }
            },
            .pause => {
                // for (pause_mode.systems) |sys| {
                //     try sys(pause_mode);
                // }
            },
        };
    }

    pub fn draw(mode: *Mode) !void {
        switch (mode.*) {
            .play => |play_mode| try play_mode.draw(),
            .pause => |pause_mode| try pause_mode.draw(),
        }
    }
};

/// Playdate or terminal
runtime: game.AnyRuntime,
/// Describes in which sequence everything should be drawn
render: Render,
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
mode: Mode = undefined,

pub fn create(runtime: game.AnyRuntime) !*Self {
    const session = try runtime.alloc.create(Self);
    session.* = .{
        .runtime = runtime,
        .render = .{},
        .screen = game.Screen.init(game.DISPLAY_DUNG_ROWS, game.DISPLAY_DUNG_COLS, game.Dungeon.Region),
        .entities = try ecs.EntitiesManager.init(runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
    };
    session.query = .{ .entities = &session.entities, .components = &session.components };
    const player_and_position = try initLevel(session.dungeon, &session.entities, &session.components);
    session.player = player_and_position[0];
    session.screen.centeredAround(player_and_position[1]);

    session.play();

    return session;
}

pub fn play(session: *Self) void {
    const target = switch (session.mode) {
        .pause => |pause_mode| pause_mode.target,
        else => session.player,
    };
    session.mode.deinit();
    session.mode = .{ .play = game.PlayMode.init(session, target) };
}

pub fn pause(session: *Self) !void {
    session.mode.deinit();
    session.mode = .{ .pause = try game.PauseMode.init(session) };
}

pub fn destroy(self: *Self) void {
    self.entities.deinit();
    self.components.deinit();
    self.dungeon.destroy();
    self.mode.deinit();
    self.runtime.alloc.destroy(self);
}

pub fn tick(self: *Self) anyerror!void {
    // Nothing should happened until the player pushes a button
    if (try self.runtime.readPushedButtons()) |btn| {
        try self.mode.handleInput(btn);
        // TODO add speed score for actions
        // We should not run a new action until finish previous one
        while (self.components.getForEntity(self.player, game.Action)) |_| {
            try self.mode.runSystems();
            try self.render.render(self);
        }
    }
    // rendering should be independent on input,
    // to be able to play animations
    try self.render.render(self);
}

pub fn entityAt(session: *game.GameSession, place: p.Point) ?game.Entity {
    for (session.components.arrayOf(game.Sprite).components.items, 0..) |sprite, idx| {
        if (sprite.position.eql(place)) {
            return session.components.arrayOf(game.Sprite).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

pub fn removeEntity(self: *Self, entity: game.Entity) !void {
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
    try components.setToEntity(door, game.Sprite{ .position = door_at.*, .codepoint = '+' });
}

fn initPlayer(
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
    init_position: p.Point,
) !game.Entity {
    const player = try entities.newEntity();
    try components.setToEntity(player, game.Sprite{ .codepoint = '@', .position = init_position });
    try components.setToEntity(player, game.Health{ .hp = 100 });
    return player;
}

fn addRat(
    dungeon: *game.Dungeon,
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
) !void {
    if (randomEmptyPlace(dungeon, components)) |position| {
        const rat = try entities.newEntity();
        try components.setToEntity(rat, game.Sprite{ .codepoint = 'r', .position = position });
        try components.setToEntity(rat, game.Description{ .name = "Rat" });
        try components.setToEntity(rat, game.Health{ .hp = 10 });
    }
}

fn randomEmptyPlace(dungeon: *game.Dungeon, components: *const ecs.ComponentsManager(game.Components)) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = dungeon.randomPlace();
        var is_empty = true;
        for (components.getAll(game.Sprite)) |sprite| {
            if (sprite.position.eql(place)) {
                is_empty = false;
            }
        }
        if (is_empty) return place;
    }
    return null;
}
