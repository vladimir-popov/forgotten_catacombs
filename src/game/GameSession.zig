//! This is the root object for a single game session.
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

const GameSession = @This();

pub const Mode = union(enum) {
    play: PlayMode,
    explore: ExploreMode,
    looking_around: LookingAroundMode,

    inline fn deinit(self: Mode) void {
        switch (self) {
            .play => self.play.deinit(),
            .looking_around => self.looking_around.deinit(),
            .explore => {},
        }
    }
};

arena: std.heap.ArenaAllocator,
/// This seed should help to make all levels of the single game session reproducible.
seed: u64,
/// The PRNG initialized by the session's seed. This prng is used to make any dynamic decision by AI, or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
ai: g.AI,
runtime: g.Runtime,
/// Buffered render to draw the game
render: g.Render,
/// Visible area
viewport: g.Viewport,
///
events: g.events.EventBus,
/// The current level
level: g.Level,
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
        .ai = g.AI{ .session = self, .rand = self.prng.random() },
        .runtime = runtime,
        .render = render,
        .viewport = g.Viewport.init(render.scene_rows, render.scene_cols),
        .events = g.events.EventBus.init(&self.arena),
        .level = undefined,
        .mode = .{ .play = undefined },
        .is_game_over = false,
    };
    try g.Levels.firstLevel(&self.level, self.arena.allocator(), g.entities.Player, true);
    self.viewport.region.top_left = .{ .row = 1, .col = 1 };
    try self.events.subscribe(self.viewport.subscriber());
    try self.mode.play.init(self.arena.allocator(), self, null);
}

pub fn deinit(self: *GameSession) void {
    self.arena.deinit();
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play = undefined };
    try self.mode.play.init(self.arena.allocator(), self, entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .explore = try ExploreMode.init(self) };
}

pub fn lookAround(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .looking_around = undefined };
    try self.mode.looking_around.init(self.arena.allocator(), self);
}

pub fn subscriber(self: *GameSession) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *GameSession = @ptrCast(@alignCast(ptr));
    switch (event) {
        .player_hit => {
            log.debug("Update target after player hit", .{});
            try self.mode.play.updateQuickActions(event.player_hit.target);
        },
        .entity_moved => |entity_moved| if (entity_moved.entity == self.session.level.player) {
            try self.level.onPlayerMoved(entity_moved);
        },
        .entity_died => if (event.entity_died.is_player) {
            self.is_game_over = true;
        },
        else => {},
    }
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.mode.play.tick(),
        .explore => try self.mode.explore.tick(),
        .looking_around => try self.mode.looking_around.tick(),
    }
    try self.events.notifySubscribers();
}

/// Handles intentions to do some actions
pub fn doAction(self: *GameSession, actor: g.Entity, action: g.Action, actor_speed: g.MovePoints) !g.MovePoints {
    if (std.log.logEnabled(.debug, .action_system) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), actor });
    }
    switch (action) {
        .move => |move| {
            if (self.level.components.getForEntity(actor, c.Position)) |position|
                return doMove(self, actor, position, move.target, actor_speed);
        },
        .hit => |hit| {
            return doHit(self, actor, hit.by_weapon, actor_speed, hit.target, hit.target_health);
        },
        .open => |door| {
            try self.level.components.setComponentsToEntity(door, g.entities.OpenedDoor);
        },
        .close => |door| {
            try self.level.components.setComponentsToEntity(door, g.entities.ClosedDoor);
        },
        .move_to_level => |ladder| {
            try self.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            self.level.components.getForEntityUnsafe(target, c.EnemyState).* = .sleeping;
            try self.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.go_sleep },
            );
        },
        .chill => |target| {
            self.level.components.getForEntityUnsafe(target, c.EnemyState).* = .walking;
            try self.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.relax },
            );
        },
        .get_angry => |target| {
            self.level.components.getForEntityUnsafe(target, c.EnemyState).* = .aggressive;
            try self.level.components.setToEntity(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.get_angry },
            );
        },
        else => {},
    }
    return actor_speed;
}

fn doMove(
    self: *GameSession,
    entity: g.Entity,
    from_position: *c.Position,
    target: g.Action.Move.Target,
    move_speed: g.MovePoints,
) anyerror!g.MovePoints {
    const new_place = switch (target) {
        .direction => |direction| from_position.point.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.point.eql(new_place)) return 0;

    if (checkCollision(self, entity, new_place)) |action| {
        return try doAction(self, entity, action, move_speed);
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity == self.level.player),
            .moved_from = from_position.point,
            .target = target,
        },
    };
    from_position.point = new_place;
    try self.events.sendEvent(event);
    return move_speed;
}

fn checkCollision(self: *GameSession, actor: g.Entity, place: p.Point) ?g.Action {
    if (self.level.obstacleAt(place)) |obstacle| {
        switch (obstacle) {
            .landscape => return .do_nothing,
            .door => |door| return .{ .open = door },
            .entity => |entity| {
                if (self.level.components.getForEntity(entity, c.Health)) |health|
                    if (self.level.components.getForEntity(actor, c.Weapon)) |weapon|
                        return .{ .hit = .{ .target = entity, .target_health = health, .by_weapon = weapon } };
            },
        }
    }
    return null;
}

fn doHit(
    self: *GameSession,
    actor: g.Entity,
    actor_weapon: *const c.Weapon,
    actor_speed: g.MovePoints,
    enemy: g.Entity,
    enemy_health: *c.Health,
) !g.MovePoints {
    const damage = actor_weapon.generateDamage(self.prng.random());
    log.debug("The entity {d} received damage {d} from {d}", .{ enemy, damage, actor });
    enemy_health.current -= @as(i16, @intCast(damage));
    try self.level.components.setToEntity(
        enemy,
        c.Animation{ .frames = &c.Animation.FramesPresets.hit },
    );
    if (actor == self.level.player) {
        try self.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
    if (enemy_health.current <= 0) {
        log.debug("The entity {d} is died", .{enemy});
        try self.level.removeEntity(enemy);
        try self.events.sendEvent(
            g.events.Event{
                .entity_died = .{ .entity = enemy, .is_player = (enemy == self.level.player) },
            },
        );
    }
    return actor_speed;
}

fn movePlayerToLevel(self: *GameSession, by_ladder: c.Ladder) !void {
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
    try self.mode.play.updateQuickActions(null);
    self.viewport.centeredAround(self.level.playerPosition().point);
}
