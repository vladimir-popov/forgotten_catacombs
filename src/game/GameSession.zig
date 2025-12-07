//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `ExploreMode`, `ExploreLevelMode` and so on. That modes are part of the
//! GameSession extracted to the separate files to make their maintenance easier.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const ActionSystem = @import("ActionSystem.zig");
pub const ExploreLevelMode = @import("game_modes/ExploreLevelMode.zig");
pub const ExploreMode = @import("game_modes/ExploreMode.zig");
pub const InventoryMode = @import("game_modes/InventoryMode.zig");
pub const PlayMode = @import("game_modes/PlayMode.zig");
pub const SaveLoadMode = @import("game_modes/SaveLoadMode.zig");
pub const TradingMode = @import("game_modes/TradingMode.zig");

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
/// This seed should help to make all levels of a single game session reproducible.
seed: u64,
/// The PRNG initialized with the current time.
/// This prng should be used to make any dynamic decision by AI, or game events,
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
journal: g.Journal,
///
events: g.events.EventBus,
player: g.Entity,
/// The current level
level: g.Level,
/// The deepest achieved level
max_depth: u8,
/// The current mode of the game
mode: Mode,
///
actions: ActionSystem,

/// Two cases of initialization exists:
///  1. Creating a new Game Session;
///  2. Loading existed Game Session;
/// To create a fully initialized new session the `initNew` method should be used.
/// To load session the follow steps should be passed:
///  1. `preInit` sets up external dependencies, initializes inner containers and the viewport.
///  2. the seed should be set up;
///  4. the player should be added to the session;
///  5. the max depth should be set up;
///  6. the level should be completely initialized;
///  7. `completeInitialization` subscribes the viewport and the game session itself on events;
///    move the viewport to the player; changes the inner state to the `play` mode.
///
pub fn preInit(
    self: *GameSession,
    game_arena_allocator: std.mem.Allocator,
    runtime: g.Runtime,
    render: g.Render,
) !void {
    self.* = .{
        .actions = .{},
        .arena = std.heap.ArenaAllocator.init(game_arena_allocator),
        .runtime = runtime,
        .render = render,
        .viewport = g.Viewport.init(render.scene_rows, render.scene_cols),
        .registry = try g.Registry.init(self.arena.allocator()),
        .events = g.events.EventBus.init(&self.arena),
        .seed = 0,
        .max_depth = 0,
        .prng = std.Random.DefaultPrng.init(runtime.currentMillis()),
        .ai = g.AI{ .session = self, .rand = self.prng.random() },
        .journal = undefined,
        .player = undefined,
        .level = undefined,
        .mode = undefined,
    };
    log.debug("The game session is preinited", .{});
}

/// This method is idempotent. It does the following:
///  - initializes a journal;
///  - subscribes event handlers;
///  - puts the viewport around the player;
///  - switches the game session to the `play` mode.
pub fn completeInitialization(self: *GameSession) !void {
    self.journal = try g.Journal.init(self.arena.allocator(), &self.registry, self.seed);
    try self.events.subscribe(self.viewport.subscriber());
    try self.events.subscribe(self.subscriber());
    self.viewport.centeredAround(self.level.playerPosition().place);
    log.debug(
        "The game session is completely initialized. Seed {d}; Max depth {d}; Player id {d}",
        .{ self.seed, self.max_depth, self.player.id },
    );
}

/// Completely initializes an undefined GameSession.
pub fn initNew(
    self: *GameSession,
    gpa: std.mem.Allocator,
    seed: u64,
    runtime: g.Runtime,
    render: g.Render,
    stats: c.Stats,
    skills: c.Skills,
) !void {
    log.debug("Begin a new game session with seed {d}", .{seed});
    try self.preInit(gpa, runtime, render);
    self.seed = seed;
    self.player = try self.registry.addNewEntity(
        try g.entities.player(self.registry.allocator(), stats, skills),
    );

    // Creates the initial equipment of the player
    self.registry.getUnsafe(self.player, c.Wallet).money += 200;
    var equipment: *c.Equipment = self.registry.getUnsafe(self.player, c.Equipment);
    var invent: *c.Inventory = self.registry.getUnsafe(self.player, c.Inventory);
    const weapon = try self.registry.addNewEntity(g.presets.Items.values.get(.pickaxe).*);
    const light = try self.registry.addNewEntity(g.presets.Items.values.get(.torch).*);
    equipment.weapon = weapon;
    equipment.light = light;
    try invent.items.add(weapon);
    try invent.items.add(light);

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

pub fn switchModeToLoadingSession(self: *GameSession) !void {
    log.debug("Start loading a game session", .{});
    self.mode = .{ .save_load = SaveLoadMode.loadSession(self) };
}

/// Changes the mode to the SaveLoadMode.
/// The next process after saving the session will be `.go_to_welcome_screen`.
/// That means that the `error.GoToMainMenu` will be returned on next tick.
pub fn switchModeToSavingSession(self: *GameSession) void {
    self.mode.deinit();
    self.mode = .{ .save_load = SaveLoadMode.saveSession(self) };
}

/// Produces an event to change the mode to `PlayMode`.
/// Receives continuations: arguments to recover the previous state of the `PlayMode`.
///  - `entity_in_focus` - an entity that should be targeted in focus; This is either previous
///    target, or a new target from the `LookingAround` mode.
///  - `action` - an action to perform; Usually is action initiated during manage the inventory.
pub fn continuePlay(self: *GameSession, entity_in_focus: ?g.Entity, action: ?g.actions.Action) !void {
    log.debug("Continue playing with entity_in_focus {any}, action {any}", .{ entity_in_focus, action });
    try self.events.sendEvent(
        .{ .mode_changed = .{ .to_play = .{ .entity_in_focus = entity_in_focus, .action = action } } },
    );
}

// should not be invoked outside. `continuePlay` should be used instead
fn switchModeToPlay(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play = undefined };
    try self.render.redrawFromSceneBuffer();
    try self.mode.play.init(self.arena.allocator(), self, entity_in_focus);
}

pub fn explore(self: *GameSession) !void {
    try self.events.sendEvent(.{ .mode_changed = .to_explore });
}

pub fn lookAround(self: *GameSession) !void {
    try self.events.sendEvent(.{ .mode_changed = .to_looking_around });
}

pub fn manageInventory(self: *GameSession) !void {
    try self.events.sendEvent(.{ .mode_changed = .to_inventory });
}

pub fn trade(self: *GameSession, shop: *c.Shop) !void {
    try self.events.sendEvent(.{ .mode_changed = .{ .to_trading = shop } });
}

pub fn movePlayerToLevel(self: *GameSession, by_ladder: c.Ladder) !void {
    try self.events.sendEvent(.{ .level_changed = .{ .by_ladder = by_ladder } });
}

pub fn onEntityDied(self: *GameSession, entity: g.Entity) !void {
    if (entity.eql(self.player)) {
        log.info("Player is dead. Game is over.", .{});
        // return error for break the game loop:
        return error.GameOver;
    } else {
        log.debug("NPC {d} is dead", .{entity.id});
        try self.journal.markEnemyAsKnown(entity);
        try self.registry.removeEntity(entity);
        try self.level.removeEntity(entity);
        try self.events.sendEvent(.{ .entity_died = entity });
    }
}

/// Handles events on the end of the `tick`
fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *GameSession = @ptrCast(@alignCast(ptr));
    switch (event) {
        .mode_changed => |new_mode| switch (new_mode) {
            .to_play => |args| {
                try self.switchModeToPlay(args.entity_in_focus);
                if (args.action) |action| {
                    _ = try self.mode.play.doTurn(self.player, action);
                }
            },
            .to_explore => {
                self.mode.deinit();
                self.mode = .{ .explore_level = try ExploreLevelMode.init(self) };
            },
            .to_looking_around => {
                self.mode.deinit();
                self.mode = .{ .explore = undefined };
                try self.mode.explore.init(self.arena.allocator(), self);
            },
            .to_inventory => {
                if (self.registry.get2(self.player, c.Equipment, c.Inventory)) |tuple| {
                    self.mode.deinit();
                    self.mode = .{ .inventory = undefined };
                    const drop = self.level.itemAt(self.level.playerPosition().place);
                    try self.mode.inventory.init(self.arena.allocator(), self, tuple[0], tuple[1], drop);
                }
            },
            .to_trading => |shop| {
                self.mode.deinit();
                self.mode = .{ .trading = undefined };
                try self.mode.trading.init(self.arena.allocator(), self, shop);
            },
        },
        .level_changed => |lvl| {
            self.mode.deinit();
            self.mode = .{ .save_load = try SaveLoadMode.loadOrGenerateLevel(self, lvl.by_ladder) };
        },
        .entity_moved => |entity_moved| {
            if (entity_moved.entity.id == self.player.id) {
                try self.level.onPlayerMoved(entity_moved);
            }
        },
        .entity_died => |entity| {
            log.debug("The enemy {d} has been died", .{entity.id});
        },
    }
}

pub fn playerMovedToLevel(self: *GameSession) !void {
    self.max_depth = @max(self.max_depth, self.level.depth);
    self.viewport.centeredAround(self.level.playerPosition().place);
    try self.switchModeToPlay(null);
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

pub fn subscriber(self: *GameSession) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
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
