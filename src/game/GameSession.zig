//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `ExploreMode`, `ExploreLevelMode` and so on. That modes are part of the
//! GameSession extracted to the separate files to make their maintenance easier.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const ExploreLevelMode = @import("game_modes/ExploreLevelMode.zig");
const ExploreMode = @import("game_modes/ExploreMode.zig");
const InventoryMode = @import("game_modes/InventoryMode.zig");
const PlayMode = @import("game_modes/PlayMode.zig");
const SaveLoadMode = @import("game_modes/SaveLoadMode.zig");
const TradingMode = @import("game_modes/TradingMode.zig");

const log = std.log.scoped(.game_session);

const GameSession = @This();

pub const Mode = union(enum) {
    explore: ExploreMode,
    explore_level: ExploreLevelMode,
    inventory: InventoryMode,
    play: PlayMode,
    save_load: SaveLoadMode,
    trading: TradingMode,

    inline fn deinit(self: *Mode) void {
        switch (self.*) {
            .explore => self.explore.deinit(),
            .explore_level => {},
            .inventory => self.inventory.deinit(),
            .play => self.play.deinit(),
            .save_load => self.save_load.deinit(),
            .trading => self.trading.deinit(),
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
entities: g.Entities,
///
events: g.events.EventBus,
player: g.Entity,
/// The current level
level: g.Level,
/// The deepest achieved level
max_depth: u8,
/// The current mode of the game
mode: Mode,

/// Two cases of initialization exists:
///  1. Creating a new Game Session;
///  2. Loading existed Game Session;
/// To create a fully initialized new session the `initNew` method should be used.
/// To load session the follow steps should be passed:
///  1. `preInit` sets up external dependencies, initializes inner containers and the viewport.
///  2. the seed should be set up;
///  3. the potions colors should be set up;
///  4. the player should be added to the session;
///  5. the max depth should be set up;
///  6. the level should be completely initialized;
///  7. `completeInitialization` subscribes the viewport and the game session itself on events;
///    move the viewport to the player; changes the inner state to the `play` mode.
///
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
        .entities = .{ .registry = try g.Registry.init(self.arena.allocator()) },
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
    self.player = try self.entities.registry.addNewEntity(try g.entities.player(self.entities.registry.allocator()));
    try self.equipPlayer();
    self.max_depth = 0;
    self.level = g.Level.preInit(self.arena.allocator(), &self.entities);
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
    self.entities.registry.getUnsafe(self.player, c.Wallet).money += 200;

    var equipment: *c.Equipment = self.entities.registry.getUnsafe(self.player, c.Equipment);
    var invent: *c.Inventory = self.entities.registry.getUnsafe(self.player, c.Inventory);
    const weapon = try self.entities.registry.addNewEntity(g.entities.Pickaxe);
    const light = try self.entities.registry.addNewEntity(g.entities.Torch);
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
    try self.render.redrawFromSceneBuffer();
    try self.mode.play.init(self.arena.allocator(), self, entity_in_focus);
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

pub fn manageInventory(self: *GameSession) !void {
    if (self.entities.registry.get2(self.player, c.Equipment, c.Inventory)) |tuple| {
        self.mode.deinit();
        self.mode = .{ .inventory = undefined };
        const drop = self.level.itemAt(self.level.playerPosition().place);
        try self.mode.inventory.init(self.arena.allocator(), self, tuple[0], tuple[1], drop);
    }
}

pub fn trade(self: *GameSession, shop: *c.Shop) !void {
    self.mode.deinit();
    self.mode = .{ .trading = undefined };
    try self.mode.trading.init(self.arena.allocator(), self, shop);
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

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .explore => try self.mode.explore.tick(),
        .explore_level => try self.mode.explore_level.tick(),
        .inventory => try self.mode.inventory.tick(),
        .play => try self.mode.play.tick(),
        .save_load => try self.mode.save_load.tick(),
        .trading => try self.mode.trading.tick(),
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
        .entity_moved => |entity_moved| {
            if (entity_moved.entity.id == self.player.id) {
                try self.level.onPlayerMoved(entity_moved);
            } else if (entity_moved.targetPlace().near8(self.level.playerPosition().place)) {
                try self.mode.play.updateQuickActions(entity_moved.entity, null);
            }
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
            if (self.entities.registry.get(actor, c.Position)) |position|
                return doMove(self, actor, position, move.target, actor_speed);
        },
        .hit => |target| {
            try doHit(self, actor, target);
            return actor_speed;
        },
        .open => |door| {
            try self.entities.registry.setComponentsToEntity(door.id, g.entities.openedDoor(door.place));
        },
        .close => |door| {
            try self.entities.registry.setComponentsToEntity(door.id, g.entities.closedDoor(door.place));
        },
        .pickup => |item| {
            const inventory = self.entities.registry.getUnsafe(self.player, c.Inventory);
            if (self.entities.registry.get(item, c.Pile)) |_| {
                try self.manageInventory();
                return 0;
            } else {
                try inventory.items.add(item);
                try self.entities.registry.remove(item, c.Position);
                try self.level.removeEntity(item);
            }
        },
        .move_to_level => |ladder| {
            try self.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            self.entities.registry.getUnsafe(target, c.EnemyState).* = .sleeping;
            try self.entities.registry.set(
                target,
                c.Animation{ .preset = .go_sleep },
            );
        },
        .chill => |target| {
            self.entities.registry.getUnsafe(target, c.EnemyState).* = .walking;
            try self.entities.registry.set(
                target,
                c.Animation{ .preset = .relax },
            );
        },
        .get_angry => |target| {
            self.entities.registry.getUnsafe(target, c.EnemyState).* = .aggressive;
            try self.entities.registry.set(
                target,
                c.Animation{ .preset = .get_angry },
            );
        },
        .trade => |shop| {
            try self.trade(shop);
            return 0;
        },
        .wait => {
            try self.entities.registry.set(actor, c.Animation{ .preset = .wait, .is_blocked = self.player.eql(actor) });
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

    if (self.checkCollision(new_place)) |action| {
        return try self.doAction(entity, action, move_speed);
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
/// {place} a place in the dungeon with which collision should be checked.
fn checkCollision(self: *GameSession, place: p.Point) ?g.Action {
    switch (self.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return null,

        .entities => |entities| {
            if (entities[2]) |entity| {
                if (self.entities.registry.get(entity, c.Door)) |_|
                    return .{ .open = .{ .id = entity, .place = place } };

                if (self.entities.isEnemy(entity))
                    return .{ .hit = entity };

                if (self.entities.registry.get(entity, c.Shop)) |shop| {
                    return .{ .trade = shop };
                }

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
    enemy: g.Entity,
) !void {
    if (self.entities.registry.get(enemy, c.Health)) |enemy_health| {
        const weapon = self.entities.getWeapon(actor) orelse {
            log.err("Actor {d} doesn't have any weapon", .{actor.id});
            return;
        };

        // Applying physical damage
        const damage = self.prng.random().intRangeLessThan(u8, weapon.damage_min, weapon.damage_max);
        doDamage(damage, weapon.damage_type, enemy_health);

        // Applying all effects of the weapon
        if (weapon.effects.len > 0) {
            const impacts = try self.entities.registry.getOrSet(enemy, c.Impacts, .{});
            var itr = weapon.effects.constIterator(0);
            while (itr.next()) |effect| {
                impacts.add(effect);
            }
            try makeImpacts(impacts, enemy_health);
            if (impacts.isNothing()) {
                try self.entities.registry.remove(enemy, c.Impacts);
            }
        }

        // a special case to give to player a chance to notice what happened
        const is_blocked_animation = actor.eql(self.player) or enemy.eql(self.player);
        try self.entities.registry.set(enemy, c.Animation{ .preset = .hit, .is_blocked = is_blocked_animation });
        if (actor.eql(self.player)) {
            try self.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
        }
        if (enemy_health.current == 0) {
            try self.entities.registry.removeEntity(enemy);
            try self.level.removeEntity(enemy);
            if (enemy.eql(self.player)) {
                log.info("Player is dead. Game over.", .{});
                return error.GameOver;
            } else {
                log.debug("The enemy {d} has been died", .{enemy.id});
            }
        }
    }
}

fn makeImpacts(
    impacts: *c.Impacts,
    target_health: *c.Health,
) !void {
    inline for (std.meta.fields(c.Impacts.Type)) |impact_field| {
        const impact_type: c.Impacts.Type = @enumFromInt(impact_field.value);
        if (@field(impacts, impact_field.name)) |*impact| {
            switch (impact_type) {
                .burning => doDamage(impact.power, .fire, target_health),
                .corrosion => doDamage(impact.power, .acid, target_health),
                .poisoning => doDamage(impact.power, .poison, target_health),
                .healing => target_health.add(impact.power),
            }
            impact.power -|= impact.decrease;
            if (impact.power == 0) {
                @field(impacts, impact_field.name) = null;
            }
        }
    }
}

fn doDamage(value: u8, damage_type: c.DamageType, target_health: *c.Health) void {
    _ = damage_type;
    target_health.current -|= value;
}
