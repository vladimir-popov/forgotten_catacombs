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
    quick_action: ?game.Action = null,
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
target_entity: ?EntityInFocus = null,

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

    // Register systems:
    try session.systems.append(game.doActions);
    try session.systems.append(game.handleCollisions);
    try session.systems.append(game.handleDamage);
    try session.systems.append(updateTarget);

    // for cases when player appears near entities
    session.findTarget();
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

pub fn openDoor(self: *Self, door: game.Entity) !void {
    if (self.components.getForEntity(door, game.Sprite)) |s| {
        try self.components.setToEntity(door, game.Door.opened);
        try self.components.setToEntity(door, game.Sprite{ .position = s.position, .codepoint = '\'' });
    }
}

pub fn closeDoor(self: *Self, door: game.Entity) !void {
    if (self.components.getForEntity(door, game.Sprite)) |s| {
        try self.components.setToEntity(door, game.Door.closed);
        try self.components.setToEntity(door, game.Sprite{ .position = s.position, .codepoint = '+' });
    }
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

fn updateTarget(session: *Self) anyerror!void {
    if (!session.keepEntityInFocus())
        session.findTarget();
}

fn findTarget(session: *Self) void {
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    // TODO improve:
    // Check the nearest entities:
    const region = p.Region{
        .top_left = .{
            .row = @max(player_position.row - 1, 1),
            .col = @max(player_position.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    };
    const sprites = session.components.arrayOf(game.Sprite);
    for (sprites.components.items, 0..) |*sprite, idx| {
        if (region.containsPoint(sprite.position)) {
            if (sprites.index_entity.get(@intCast(idx))) |entity| {
                if (session.player != entity) {
                    session.target_entity = .{ .entity = entity, .quick_action = null };
                    session.calculateQuickActionForTarget(player_position, &session.target_entity.?);
                    return;
                }
            }
        }
    }
}

/// Returns true if the focus is kept
fn keepEntityInFocus(session: *Self) bool {
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    if (session.target_entity) |*target| {
        // Check if we can keep the current quick action and target
        if (target.quick_action) |qa| {
            if (session.components.getForEntity(target.entity, game.Sprite)) |target_sprite| {
                if (player_position.near(target_sprite.position)) {
                    // handle a case when player entered to the door
                    switch (qa) {
                        .open => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .closed and !player_position.eql(target_sprite.position)) return true;
                        },
                        .close => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .opened and !player_position.eql(target_sprite.position)) return true;
                        },
                        else => return true,
                    }
                }
            }
        } else {
            session.calculateQuickActionForTarget(player_position, target);
            if (session.target_entity.?.quick_action != null) return true;
        }
    }
    session.target_entity = null;
    return false;
}

fn calculateQuickActionForTarget(
    session: *Self,
    player_position: p.Point,
    target_entity: *EntityInFocus,
) void {
    if (session.components.getForEntity(target_entity.entity, game.Sprite)) |target_sprite| {
        if (player_position.near(target_sprite.position)) {
            if (session.components.getForEntity(target_entity.entity, game.Health)) |_| {
                target_entity.quick_action = .{ .hit = target_entity.entity };
                return;
            }
            if (session.components.getForEntity(target_entity.entity, game.Door)) |door| {
                if (!player_position.eql(target_sprite.position))
                    target_entity.quick_action = switch (door.*) {
                        .opened => .{ .close = target_entity.entity },
                        .closed => .{ .open = target_entity.entity },
                    };
                return;
            }
        }
    }
}

pub fn chooseNextEntity(session: *Self) void {
    _ = session;
}
