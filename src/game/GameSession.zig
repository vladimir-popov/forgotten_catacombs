const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const game = @import("game.zig");

const Render = @import("Render.zig");
const InputHandler = @import("InputHandler.zig");

const log = std.log.scoped(.GameSession);

const Self = @This();

const System = *const fn (game: *Self) anyerror!void;

const State = enum {
    play,
    pause,
};

const EntityInFocus = struct {
    entity: game.Entity,
    quick_action: ?game.Action,
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
/// Game mechanics
systems: std.ArrayList(System),
/// Visible area
screen: game.Screen,
/// The current state of the game    
state: State = .play,
/// The pointer to the current dungeon
dungeon: *game.Dungeon,
/// Entity of the player
player: game.Entity = undefined,
/// An entity in player's focus to which a quick action can be applied
entity_in_focus: ?EntityInFocus = null,

pub fn create(runtime: game.AnyRuntime) !*Self {
    const session = try runtime.alloc.create(Self);
    session.* = .{
        .runtime = runtime,
        .render = .{},
        .screen = game.Screen.init(game.DISPLAY_DUNG_ROWS, game.DISPLAY_DUNG_COLS, game.Dungeon.Region),
        .entities = try ecs.EntitiesManager.init(runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(runtime.alloc),
        .systems = std.ArrayList(System).init(runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
    };
    session.query = .{ .entities = &session.entities, .components = &session.components };
    const player_and_position = try initLevel(session.dungeon, &session.entities, &session.components);
    session.player = player_and_position[0];
    session.screen.centeredAround(player_and_position[1]);

    // Initialize systems:
    try session.systems.append(game.doActions);
    try session.systems.append(game.handleCollisions);
    try session.systems.append(game.handleDamage);
    try session.systems.append(keepEntityInFocus);

    // for cases when player appears near entities
    try session.keepEntityInFocus();
    return session;
}

pub fn destroy(self: *Self) void {
    self.entities.deinit();
    self.components.deinit();
    self.systems.deinit();
    self.dungeon.destroy();
    self.runtime.alloc.destroy(self);
}

pub fn tick(self: *Self) anyerror!void {
    // Nothing should happened until the player pushes a button
    if (try self.runtime.readPushedButtons()) |btn| {
        try InputHandler.handleInput(self, btn);
        // TODO add speed score for actions
        // We should not run a new action until finish previous one
        while (self.components.getForEntity(self.player, game.Action)) |_| {
            for (self.systems.items) |system| {
                try system(self);
            }
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
    const player_position = dungeon.randomPlace();
    const player = try initPlayer(entities, components, player_position);
    for (0..dungeon.rand.uintLessThan(u8, 10) + 10) |_| {
        try addRat(dungeon, entities, components);
    }

    return .{ player, player_position };
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
        if (dungeon.cellAt(place)) |cl| if (cl == .floor) {
            var is_empty = true;
            for (components.getAll(game.Sprite)) |sprite| {
                if (sprite.position.eql(place)) {
                    is_empty = false;
                }
            }
            if (is_empty) return place;
        };
    }
    return null;
}

pub fn keepEntityInFocus(session: *Self) anyerror!void {
    const player_position = if (session.components.getForEntity(session.player, game.Sprite)) |player|
        player.position
    else
        return;

    if (session.entity_in_focus) |target| {
        // Check if we should change the current quick action or not
        if (target.quick_action) |qa| {
            const target_position = switch (qa) {
                .open => |at| at,
                .close => |at| at,
                else => if (session.components.getForEntity(target.entity, game.Sprite)) |s| s.position else null,
            };
            if (target_position) |tp| if (player_position.near(tp)) return;
        }
        session.calculateQuickAction(player_position, target.entity);
        return;
    }

    // Check the nearest entities:
    // TODO improve:
    const sprites = session.components.arrayOf(game.Sprite);
    const region = p.Region{
        .top_left = .{
            .row = @max(player_position.row - 1, 1),
            .col = @max(player_position.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    };
    for (sprites.components.items, 0..) |sprite, idx| {
        if (region.containsPoint(sprite.position)) {
            if (sprites.index_entity.get(@intCast(idx))) |entity| {
                if (session.player != entity) {
                    session.calculateQuickAction(player_position, entity);
                    return;
                }
            }
        }
    }
}

pub fn chooseNextEntity(session: *Self) void {
    _ = session;
}

fn calculateQuickAction(session: *Self, player_position: p.Point, target: game.Entity) void {
    if (session.components.getForEntity(target, game.Sprite)) |s| {
        if (player_position.near(s.position)) {
            session.entity_in_focus = .{
                .entity = target,
                .quick_action = if (session.components.getForEntity(target, game.Health)) |_|
                    .{ .hit = target }
                else
                    null,
            };
            return;
        }
    }
    session.entity_in_focus = .{ .entity = target, .quick_action = null };
}
