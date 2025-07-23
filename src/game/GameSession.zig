//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `ExploreMode`, `ExploreLevelMode` and so on. That modes are part of the
//! GameSession extracted to the separate files to make their maintenance easier.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const PlayMode = @import("game_modes/PlayMode.zig");
const InventoryMode = @import("game_modes/InventoryMode.zig");
const ExploreMode = @import("game_modes/ExploreMode.zig");
const ExploreLevelMode = @import("game_modes/ExploreLevelMode.zig");
const SaveLoadMode = @import("game_modes/SaveLoadMode.zig");

const log = std.log.scoped(.game_session);

const GameSession = @This();

pub const Mode = union(enum) {
    play: PlayMode,
    inventory: InventoryMode,
    explore: ExploreMode,
    explore_level: ExploreLevelMode,
    save_load: SaveLoadMode,

    inline fn deinit(self: *Mode) void {
        switch (self.*) {
            .play => self.play.deinit(),
            .inventory => self.inventory.deinit(),
            .explore => self.explore.deinit(),
            .save_load => self.save_load.deinit(),
            .explore_level => {},
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
registry: g.Registry,
///
events: g.events.EventBus,
player: g.Entity,
/// The current level
level: g.Level,
/// The deepest achieved level
max_depth: u8,
/// The current mode of the game
mode: Mode,

/// The GameSession should be initialized in few steps:
///  - `preInit` sets up external dependencies, initializes inner containers and the viewport.
///  - the seed should be set up;
///  - the player should be added to the session;
///  - the max depth should be set up;
///  - the level should be completely initialized;
///  - `completeInitialization` subscribes the viewport and the game session itself on events;
///    move the viewport to the player; changes the inner state to the `play` mode.
pub fn preInit(
    self: *GameSession,
    gpa: std.mem.Allocator,
    runtime: g.Runtime,
    render: g.Render,
) !void {
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(gpa),
        .runtime = runtime,
        .render = render,
        .viewport = g.Viewport.init(render.scene_rows, render.scene_cols),
        .registry = try g.Registry.init(self.arena.allocator()),
        .events = g.events.EventBus.init(&self.arena),
        .seed = 0,
        .max_depth = 0,
        .prng = std.Random.DefaultPrng.init(0),
        .ai = g.AI{ .session = self, .rand = self.prng.random() },
        .player = undefined,
        .level = undefined,
        .mode = undefined,
    };
    log.debug("The game session is preinited", .{});
}

/// This method is idempotent. It does the following:
///  - subscribes event handlers;
///  - puts the viewport around the player;
///  - switches the game session to the `play` mode.
pub fn completeInitialization(self: *GameSession) !void {
    try self.events.subscribe(self.viewport.subscriber());
    try self.events.subscribe(self.subscriber());
    self.viewport.centeredAround(self.level.playerPosition().place);
    log.debug("The game session is completely initialized. Seed {d}; Max depth {d}", .{ self.seed, self.max_depth });
}

/// Completely initializes an undefined GameSession.
pub fn initNew(
    self: *GameSession,
    gpa: std.mem.Allocator,
    seed: u64,
    runtime: g.Runtime,
    render: g.Render,
) !void {
    log.debug("Begin a new game session with seed {d}", .{seed});
    try self.preInit(gpa, runtime, render);
    self.setSeed(seed);
    self.player = try self.registry.addNewEntity(try g.entities.player(self.registry.allocator()));
    try self.equipPlayer();
    self.max_depth = 0;
    self.level = g.Level.preInit(self.arena.allocator(), &self.registry);
    try self.level.initAsFirstLevel(self.player);
    try self.completeInitialization();

    self.mode = .{ .play = undefined };
    try self.mode.play.init(self.arena.allocator(), self, null);
    // hack  for the first level only
    self.viewport.region.top_left.moveNTimes(.up, 3);
}

pub fn deinit(self: *GameSession) void {
    // to be sure that all files are closed
    self.mode.deinit();
    // free memory
    self.arena.deinit();
    self.* = undefined;
    log.debug("The game session is deinited", .{});
}

pub fn setSeed(self: *GameSession, seed: u64) void {
    self.seed = seed;
    self.prng.seed(seed);
}

/// Creates the initial equipment of the player
fn equipPlayer(self: *GameSession) !void {
    var equipment: *c.Equipment = self.registry.getUnsafe(self.player, c.Equipment);
    var invent: *c.Inventory = self.registry.getUnsafe(self.player, c.Inventory);
    const weapon = try self.registry.addNewEntity(g.entities.Club);
    const light = try self.registry.addNewEntity(g.entities.Torch);
    equipment.weapon = weapon;
    equipment.light = light;
    try invent.items.add(weapon);
    try invent.items.add(light);
}

pub fn load(self: *GameSession) !void {
    log.debug("Start loading a game session", .{});
    self.mode = .{ .save_load = SaveLoadMode.loadSession(self) };
}

/// Runs the process of saving the current game session,
/// that should be finished with GoToMainMenu error on `tick()`
pub fn save(self: *GameSession) void {
    self.mode.deinit();
    self.mode = .{ .save_load = SaveLoadMode.saveSession(self) };
}

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play = undefined };
    try self.render.clearDisplay();
    try self.mode.play.init(self.arena.allocator(), self, entity_in_focus);
}

pub fn manageInventory(self: *GameSession) !void {
    if (self.registry.get2(self.player, c.Equipment, c.Inventory)) |tuple| {
        self.mode.deinit();
        self.mode = .{ .inventory = undefined };
        const drop = self.level.itemAt(self.level.playerPosition().place);
        try self.mode.inventory.init(self.arena.allocator(), self, tuple[0], tuple[1], drop);
    }
}

pub fn explore(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .explore_level = try ExploreLevelMode.init(self) };
}

pub fn lookAround(self: *GameSession) !void {
    self.mode.deinit();
    self.mode = .{ .explore = undefined };
    try self.mode.explore.init(self.arena.allocator(), self);
}

fn movePlayerToLevel(self: *GameSession, by_ladder: c.Ladder) !void {
    try self.events.sendEvent(.{ .level_changed = .{ .by_ladder = by_ladder } });
}

pub fn playerMovedToLevel(self: *GameSession) !void {
    self.max_depth = @max(self.max_depth, self.level.depth);
    self.viewport.centeredAround(self.level.playerPosition().place);
    try self.play(null);
    try self.mode.play.updateQuickActions(null, null);
    const event = g.events.Event{
        .entity_moved = .{
            .entity = self.player,
            .is_player = true,
            .moved_from = g.primitives.Point.init(0, 0),
            .target = .{ .new_place = self.level.playerPosition().place },
        },
    };
    try self.events.sendEvent(event);
}

pub fn getWeapon(self: *const GameSession, actor: g.Entity) ?*c.Weapon {
    if (self.registry.get(actor, c.Weapon)) |weapon| return weapon;

    if (self.registry.get(actor, c.Equipment)) |equipment|
        if (equipment.weapon) |weapon_id|
            if (self.registry.get(weapon_id, c.Weapon)) |weapon|
                return weapon;

    return null;
}

pub fn isEnemy(self: *const GameSession, entity: g.Entity) bool {
    return self.registry.get(entity, c.Health) != null;
}

pub fn isTool(self: *const GameSession, item: g.Entity) bool {
    return (self.registry.get(item, c.Weapon) != null) or
        (self.registry.get(item, c.SourceOfLight) != null);
}

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.mode.play.tick(),
        .inventory => try self.mode.inventory.tick(),
        .explore => try self.mode.explore.tick(),
        .explore_level => try self.mode.explore_level.tick(),
        .save_load => try self.mode.save_load.tick(),
    }
    try self.events.notifySubscribers();
}

pub fn subscriber(self: *GameSession) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *GameSession = @ptrCast(@alignCast(ptr));
    switch (event) {
        .level_changed => |lvl| {
            self.mode.deinit();
            self.mode = .{ .save_load = try SaveLoadMode.loadOrGenerateLevel(self, lvl.by_ladder) };
        },
        .player_hit => {
            log.debug("Update target after player hit", .{});
            try self.mode.play.updateQuickActions(event.player_hit.target, null);
        },
        .entity_moved => |entity_moved| if (entity_moved.entity.id == self.player.id) {
            try self.level.onPlayerMoved(entity_moved);
        },
    }
}

/// Handles intentions to do some actions
pub fn doAction(self: *GameSession, actor: g.Entity, action: g.Action, actor_speed: g.MovePoints) !g.MovePoints {
    if (std.log.logEnabled(.debug, .action_system) and action != .do_nothing) {
        log.debug("Do action {s} by the entity {d}", .{ @tagName(action), actor.id });
    }
    switch (action) {
        .do_nothing => return 0,
        .open_inventory => {
            try self.manageInventory();
            return 0;
        },
        .move => |move| {
            if (self.registry.get(actor, c.Position)) |position|
                return doMove(self, actor, position, move.target, actor_speed);
        },
        .hit => |hit| if (self.registry.get(hit.target, c.Health)) |health| {
            return doHit(self, actor, hit.by_weapon, actor_speed, hit.target, health);
        },
        .open => |door| {
            try self.registry.setComponentsToEntity(door.id, g.entities.openedDoor(door.place));
        },
        .close => |door| {
            try self.registry.setComponentsToEntity(door.id, g.entities.closedDoor(door.place));
        },
        .pickup => |item| {
            const inventory = self.registry.getUnsafe(self.player, c.Inventory);
            if (self.registry.get(item, c.Pile)) |_| {
                try self.manageInventory();
                return 0;
            } else {
                try inventory.items.add(item);
                try self.registry.remove(item, c.Position);
                try self.level.removeEntity(item);
            }
        },
        .move_to_level => |ladder| {
            try self.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            self.registry.getUnsafe(target, c.EnemyState).* = .sleeping;
            try self.registry.set(
                target,
                c.Animation{ .preset = .go_sleep },
            );
        },
        .chill => |target| {
            self.registry.getUnsafe(target, c.EnemyState).* = .walking;
            try self.registry.set(
                target,
                c.Animation{ .preset = .relax },
            );
        },
        .get_angry => |target| {
            self.registry.getUnsafe(target, c.EnemyState).* = .aggressive;
            try self.registry.set(
                target,
                c.Animation{ .preset = .get_angry },
            );
        },
        .wait => {
            try self.registry.set(actor, c.Animation{ .preset = .wait, .is_blocked = self.player.eql(actor) });
        },
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
        .direction => |direction| from_position.place.movedTo(direction),
        .new_place => |place| place,
    };
    if (from_position.place.eql(new_place)) return 0;

    if (checkCollision(self, entity, new_place)) |action| {
        return try doAction(self, entity, action, move_speed);
    }
    const event = g.events.Event{
        .entity_moved = .{
            .entity = entity,
            .is_player = (entity.eql(self.player)),
            .moved_from = from_position.place,
            .target = target,
        },
    };
    try self.events.sendEvent(event);
    from_position.place = new_place;
    return move_speed;
}

/// Returns an action that should be done because of collision.
/// The `null` means that the move is completed;
/// .do_nothing or any other action means that the move should be aborted, and the action handled;
///
/// {actor} who is making a move;
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(self: *GameSession, actor: g.Entity, place: p.Point) ?g.Action {
    switch (self.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return null,

        .entities => |entities| {
            if (entities[2]) |entity| {
                if (self.registry.get(entity, c.Door)) |_|
                    return .{ .open = .{ .id = entity, .place = place } };

                if (self.isEnemy(entity))
                    if (self.getWeapon(actor)) |weapon|
                        return .{ .hit = .{ .target = entity, .by_weapon = weapon.* } };

                // the player should not step on the place with entity with z-order = 2
                return .do_nothing;
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with z_order < 2
            return null;
        },
    }
    return .do_nothing;
}

fn doHit(
    self: *GameSession,
    actor: g.Entity,
    actor_weapon: c.Weapon,
    actor_speed: g.MovePoints,
    enemy: g.Entity,
    enemy_health: *c.Health,
) !g.MovePoints {
    const damage = actor_weapon.generateDamage(self.prng.random());
    log.debug("The entity {d} received damage {d} from entity {d}", .{ enemy.id, damage, actor.id });
    enemy_health.current -= @as(i16, @intCast(damage));
    const is_blocked_animation = actor.eql(self.player) or enemy.eql(self.player);
    try self.registry.set(enemy, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
    if (actor.eql(self.player)) {
        try self.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
    if (enemy_health.current <= 0) {
        const is_player = enemy.eql(self.player);
        log.debug("The {s} {d} died", .{ if (is_player) "player" else "enemy", enemy.id });
        try self.registry.removeEntity(enemy);
        try self.level.removeEntity(enemy);
        if (is_player) {
            log.info("Player is dead. Game over.", .{});
            return error.GameOver;
        }
    }
    return actor_speed;
}
