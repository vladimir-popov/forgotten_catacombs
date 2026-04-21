//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `ExploreMode`, `ExploreLevelMode` and so on. These modes are extracted
//! to separate files to make their maintenance easier.
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
pub const ModifyMode = @import("game_modes/ModifyMode.zig");
pub const SaveLoadMode = @import("game_modes/SaveLoadMode.zig");
pub const TradingMode = @import("game_modes/TradingMode.zig");
pub const LevelUp = @import("game_modes/LevelUp.zig");

const log = std.log.scoped(.game_session);

const Self = @This();

// zig copies a tagged union on stack in switch statement.
// this is why all values must be very compacted
pub const Mode = union(enum) {
    explore: *ExploreMode,
    explore_level: *ExploreLevelMode,
    inventory: *InventoryMode,
    level_up: *LevelUp,
    modify_recognize: *ModifyMode,
    play: *PlayMode,
    save_load: *SaveLoadMode,
    trading: *TradingMode,
};

/// This is an arena used to create this session.
/// It should be used only inside this session to manage its state (events and notifications)
root_arena: *g.GameStateArena,
/// Used to allocate memory for the current mode.
/// Should be used to allocate anything within mode.
mode_arena: g.SessionModeArena,
/// This is a main seed of the game session.
/// It should help to make all levels of a single game session reproducible.
seed: u64,
/// The PRNG initialized with the current time.
/// This PRNG should be used to make any dynamic decision by AI or game events,
/// and should not be used to generate any level objects, to keep the levels reproducible.
prng: std.Random.DefaultPrng,
//
runtime: g.Runtime,
/// Buffered render to draw the game
render: g.Render,
/// Visible area
viewport: g.Viewport,
///
registry: g.Registry,
///
journal: g.Journal,
//
ai: g.AI,
///
actions: ActionSystem,
/// The entity id of the player.
/// This id should never changes during the game session.
player: g.Entity,
/// The current level
level: g.Level,
/// The deepest achieved level
max_depth: u8,
/// How many turns have been passed from the start of this game session
spent_turns: u32,
// How many move points spent within the current turn
spent_move_points: g.MovePoints,
/// The current mode of the game
mode: Mode,
///
events: std.ArrayList(g.events.Event),
/// A pop up notifications to show.
notifications: std.Deque(g.notifications.Notification),

/// Two cases of initialization exists:
///  1. Creating a new Game Session;
///  2. Loading an existing Game Session;
/// To create a fully initialized new session, the `initNew` method should be used.
/// To load a session, the following steps should be passed:
///  1. `preInit` sets up external dependencies, initializes inner containers and the viewport.
///  2. the seed should be set up;
///  4. the player should be added to the session;
///  5. the max depth should be set up;
///  6. the level should be completely initialized;
///  7. `completeInitialization` subscribes the viewport and the game session itself to events;
///    moves the viewport to the player; changes the inner state to the `play` mode.
///
pub fn preInit(
    self: *Self,
    game_session_arena: *g.GameStateArena,
    runtime: g.Runtime,
    render: g.Render,
) !void {
    self.* = .{
        .root_arena = game_session_arena,
        .mode_arena = std.heap.ArenaAllocator.init(game_session_arena.allocator()),
        .runtime = runtime,
        .render = render,
        .viewport = g.Viewport.init(render.scene_buffer.region().rows, render.scene_buffer.region().cols),
        .registry = try g.Registry.init(game_session_arena),
        .actions = .{},
        .events = .empty,
        .seed = 0,
        .max_depth = 0,
        .spent_turns = 0,
        .spent_move_points = 0,
        .prng = std.Random.DefaultPrng.init(runtime.currentMillis()),
        .ai = g.AI{ .session = self, .rand = self.prng.random() },
        .notifications = .empty,
        .journal = undefined,
        .player = undefined,
        .level = undefined,
        .mode = undefined,
    };
    log.debug("The game session is pre-initialized", .{});
}

/// Completely initializes an undefined GameSession.
pub fn initNew(
    self: *Self,
    game_session_arena: *g.GameStateArena,
    seed: u64,
    runtime: g.Runtime,
    render: g.Render,
    stats: c.Stats,
    skills: c.Skills,
    health: c.Health,
) !void {
    log.debug("Begin a new game session with seed {d}", .{seed});
    try self.preInit(game_session_arena, runtime, render);
    self.seed = seed;
    var prng = std.Random.DefaultPrng.init(seed);
    self.player = try self.registry.addNewEntity(
        try g.entities.player(self.registry.allocator(), prng.random(), stats, skills, health),
    );

    var equipment: *c.Equipment = self.registry.getUnsafe(self.player, c.Equipment);
    var invent: *c.Inventory = self.registry.getUnsafe(self.player, c.Inventory);
    const weapon = try self.registry.addNewEntity(g.entities.presets.Items.fields.get(.pickaxe).*);
    const light = try self.registry.addNewEntity(g.entities.presets.Items.fields.get(.torch).*);
    equipment.weapon = weapon;
    equipment.light = light;
    try invent.items.add(weapon);
    try invent.items.add(light);

    self.max_depth = 0;
    self.level = g.Level.preInit(game_session_arena, &self.registry);
    try self.level.initAsFirstLevel(self.player);
    try self.completeInitialization();

    self.mode = .{ .play = try self.mode_arena.allocator().create(PlayMode) };
    try self.mode.play.init(self, null);
    // hack for the first level only
    self.viewport.region.top_left.moveNTimes(.up, 3);
}

/// This method is idempotent. It does the following:
///  - initializes a journal;
///  - subscribes event handlers;
///  - puts the viewport around the player;
///  - switches the game session to the `play` mode.
pub fn completeInitialization(self: *Self) !void {
    self.journal = try g.Journal.init(&self.registry, self.seed);
    self.viewport.centeredAround(self.level.playerPosition().place);
    log.debug(
        "The game session is completely initialized. Seed {d}; Max depth {d}; Player id {d}",
        .{ self.seed, self.max_depth, self.player.id },
    );
}

pub fn switchModeToLoadingSession(self: *Self, game_session_arena: *g.GameStateArena) !void {
    log.debug("Start loading a game session", .{});
    _ = self.mode_arena.reset(.retain_capacity);
    self.mode = .{ .save_load = try self.mode_arena.allocator().create(SaveLoadMode) };
    self.mode.save_load.* = SaveLoadMode.loadSession(self, game_session_arena);
}

/// Changes the mode to the SaveLoadMode.
/// The next process after saving the session will be `.go_to_welcome_screen`.
/// This means that the `error.GoToMainMenu` will be returned on the next tick.
pub fn switchModeToSavingSession(self: *Self) !void {
    _ = self.mode_arena.reset(.retain_capacity);
    self.mode = .{ .save_load = try self.mode_arena.allocator().create(SaveLoadMode) };
    self.mode.save_load.* = SaveLoadMode.saveSession(self);
}

/// Produces an event to change the mode to `PlayMode`.
/// Receives continuations: arguments to recover the previous state of the `PlayMode`.
///  - `entity_in_focus` - an entity that should be targeted in focus; This is either the previous
///    target or a new target from the `Explore` mode.
///  - `action` - an action to perform; Usually an action initiated during managing the inventory
///  (eat or drink as example).
pub fn continuePlay(self: *Self, entity_in_focus: ?g.Entity, action: ?g.actions.Action) !void {
    log.debug("Continue playing with entity_in_focus {any}, action {any}", .{ entity_in_focus, action });
    try self.sendEvent(
        .{ .mode_changed = .{ .to_play = .{ .entity_in_focus = entity_in_focus, .action = action } } },
    );
}

// should not be invoked outside. `continuePlay` should be used instead
fn switchModeToPlay(self: *Self, entity_in_focus: ?g.Entity) !void {
    try self.render.redrawFromSceneBuffer();
    _ = self.mode_arena.reset(.retain_capacity);
    self.mode = .{ .play = try self.mode_arena.allocator().create(PlayMode) };
    try self.mode.play.init(self, entity_in_focus);
}

pub inline fn explore(self: *Self) !void {
    try self.sendEvent(.{ .mode_changed = .to_explore });
}

pub inline fn lookAround(self: *Self) !void {
    try self.sendEvent(.{ .mode_changed = .to_looking_around });
}

pub inline fn levelUp(self: *Self) !void {
    try self.sendEvent(.{ .mode_changed = .to_level_up });
}

pub inline fn manageInventory(self: *Self) !void {
    try self.sendEvent(.{ .mode_changed = .to_inventory });
}

pub inline fn modifyRecognize(self: *Self) !void {
    try self.sendEvent(.{ .mode_changed = .to_modify_recognize });
}

pub inline fn trade(self: *Self, shop: g.Entity) !void {
    try self.sendEvent(.{ .mode_changed = .{ .to_trading = shop } });
}

pub inline fn movePlayerToLevel(self: *Self, by_ladder: c.Ladder) !void {
    try self.sendEvent(.{ .level_changed = .{ .by_ladder = by_ladder } });
}

pub inline fn removeEntity(self: *Self, entity: g.Entity) !void {
    try self.registry.removeEntity(entity);
    try self.level.removeEntity(entity);
}

/// Removes the entity or returns `error.GameOver`.
pub fn removeDeadEntity(self: *Self, entity: g.Entity) !void {
    if (entity.eql(self.player)) {
        log.info("Player is dead. Game is over.", .{});
        // return error to break the game loop:
        return error.GameOver;
    } else {
        log.debug("NPC {d} is dead", .{entity.id});
        // Handle death and remove the entity here, within the current tick
        try self.removeEntity(entity);
        try self.sendEvent(.{ .entity_died = entity });
    }
}

pub fn playerMovedToLevel(self: *Self) !void {
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
    try self.sendEvent(event);
}

pub fn showPopUpNotification(self: *Self, notification: g.notifications.Notification) !void {
    log.debug("Notification: {any}", .{notification});
    try self.notifications.pushBack(self.root_arena.allocator(), notification);
}

pub fn tick(self: *Self) !void {
    switch (self.mode) {
        .explore => try self.mode.explore.tick(),
        .explore_level => try self.mode.explore_level.tick(),
        .inventory => try self.mode.inventory.tick(),
        .level_up => try self.mode.level_up.tick(),
        .modify_recognize => try self.mode.modify_recognize.tick(),
        .play => try self.mode.play.tick(),
        .save_load => try self.mode.save_load.tick(),
        .trading => try self.mode.trading.tick(),
    }
    if (self.events.items.len > 0) {
        for (0..self.events.items.len) |event_idx| {
            try self.handleEvent(event_idx);
        }
        self.events.clearRetainingCapacity();
    }
}

pub inline fn sendEvent(self: *Self, event: g.events.Event) !void {
    try self.events.append(self.root_arena.allocator(), event);
}

/// Handles events on the end of the `tick`
noinline fn handleEvent(self: *Self, event_idx: usize) !void {
    var event = self.events.items[event_idx];
    switch (event) {
        .player_turn_completed => {
            self.spent_move_points += event.player_turn_completed.spent_move_points;
            const turns = self.spent_move_points / g.MOVE_POINTS_IN_TURN;
            self.spent_move_points = self.spent_move_points % g.MOVE_POINTS_IN_TURN;
            for (0..turns) |_| {
                self.spent_turns += 1;
                try self.actions.onTurnCompleted();
                try self.journal.onTurnCompleted();
            }
        },
        .mode_changed => |new_mode| switch (new_mode) {
            .to_play => |args| {
                try self.switchModeToPlay(args.entity_in_focus);
                if (args.action != null) {
                    const action = &(event.mode_changed.to_play.action.?);
                    _ = try self.mode.play.doTurn(self.player, action, std.math.maxInt(g.MovePoints));
                }
            },
            .to_explore => {
                _ = self.mode_arena.reset(.retain_capacity);
                self.mode = .{ .explore_level = try self.mode_arena.allocator().create(ExploreLevelMode) };
                self.mode.explore_level.* = try ExploreLevelMode.init(self);
            },
            .to_looking_around => {
                _ = self.mode_arena.reset(.retain_capacity);
                self.mode = .{ .explore = try self.mode_arena.allocator().create(ExploreMode) };
                try self.mode.explore.init(self);
            },
            .to_level_up => {
                _ = self.mode_arena.reset(.retain_capacity);
                self.mode = .{ .level_up = try self.mode_arena.allocator().create(LevelUp) };
                self.mode.level_up.* = try LevelUp.init(self);
                try self.mode.level_up.draw(self.render);
            },
            .to_inventory => {
                if (self.registry.get2(self.player, c.Equipment, c.Inventory)) |tuple| {
                    const drop = self.level.itemAt(self.level.playerPosition().place);
                    _ = self.mode_arena.reset(.retain_capacity);
                    self.mode = .{ .inventory = try self.mode_arena.allocator().create(InventoryMode) };
                    try self.mode.inventory.init(self, tuple[0], tuple[1], drop);
                }
            },
            .to_trading => |shop| {
                _ = self.mode_arena.reset(.retain_capacity);
                self.mode = .{ .trading = try self.mode_arena.allocator().create(TradingMode) };
                try self.mode.trading.init(self, shop);
            },
            .to_modify_recognize => {
                _ = self.mode_arena.reset(.retain_capacity);
                self.mode = .{ .modify_recognize = try self.mode_arena.allocator().create(ModifyMode) };
                if (self.registry.get2(self.player, c.Inventory, c.Wallet)) |tuple| {
                    try self.mode.modify_recognize.init(self, tuple[0], tuple[1]);
                }
            },
        },
        .level_changed => |lvl| {
            _ = self.mode_arena.reset(.retain_capacity);
            self.mode = .{ .save_load = try self.mode_arena.allocator().create(SaveLoadMode) };
            self.mode.save_load.* = try SaveLoadMode.loadOrGenerateLevel(self, lvl.by_ladder);
        },
        .entity_moved => |entity_moved| {
            if (entity_moved.entity.id == self.player.id) {
                try self.level.onPlayerMoved(entity_moved);
                try self.viewport.onPlayerMoved(entity_moved);
            }
        },
        .entity_died => |entity| {
            log.debug("The enemy {d} has died", .{entity.id});
        },
    }
}
