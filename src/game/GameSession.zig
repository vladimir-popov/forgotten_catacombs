//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `LookingAroundMode`, `ExploreMode` and so on. That modes are part of the
//! GameSession extracted to the separate files to make their maintenance easier.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ecs = g.ecs;

const PlayMode = @import("PlayMode.zig");
const InventoryMode = @import("InventoryMode.zig");
const ExploreMode = @import("ExploreMode.zig");
const LookingAroundMode = @import("LookingAroundMode.zig");

const log = std.log.scoped(.game_session);

const GameSession = @This();

pub const Mode = union(enum) {
    play: PlayMode,
    inventory: InventoryMode,
    explore: ExploreMode,
    looking_around: LookingAroundMode,

    inline fn deinit(self: *Mode) void {
        switch (self.*) {
            .play => self.play.deinit(),
            .inventory => self.inventory.deinit(),
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
entities: g.EntitiesManager,
///
events: g.events.EventBus,
player: g.Entity,
/// The current level
level: g.Level,
/// The current mode of the game
mode: Mode,

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
        .entities = try g.EntitiesManager.init(self.arena.allocator()),
        .player = try self.entities.addNewEntityAllocate(g.entities.player),
        .events = g.events.EventBus.init(&self.arena),
        .level = undefined,
        .mode = .{ .play = undefined },
    };
    try self.equipPlayer();
    try g.Levels.firstLevel(self.arena.allocator(), self, true);
    self.viewport.centeredAround(self.level.playerPosition().place);
    try self.events.subscribe(self.viewport.subscriber());
    try self.events.subscribe(self.subscriber());
    try self.mode.play.init(self.arena.allocator(), self, null);
}

pub fn deinit(self: *GameSession) void {
    self.arena.deinit();
}

/// Creates the initial equipment of the player
fn equipPlayer(self: *GameSession) !void {
    var equipment: *c.Equipment = self.entities.getUnsafe(self.player, c.Equipment);
    var invent: *c.Inventory = self.entities.getUnsafe(self.player, c.Inventory);
    const weapon = try self.entities.addNewEntity(g.entities.Club);
    const light = try self.entities.addNewEntity(g.entities.Torch);
    equipment.weapon = weapon;
    equipment.light = light;
    try invent.put(weapon);
    try invent.put(light);
}

// TODO: Load session from file

pub fn play(self: *GameSession, entity_in_focus: ?g.Entity) !void {
    self.mode.deinit();
    self.mode = .{ .play = undefined };
    try self.render.clearDisplay();
    try self.mode.play.init(self.arena.allocator(), self, entity_in_focus);
}

pub fn manageInventory(self: *GameSession) !void {
    if (self.entities.get2(self.player, c.Equipment, c.Inventory)) |tuple| {
        self.mode.deinit();
        self.mode = .{ .inventory = undefined };
        try self.mode.inventory.init(self.arena.allocator(), self, tuple[0], tuple[1]);
    }
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

pub inline fn tick(self: *GameSession) !void {
    switch (self.mode) {
        .play => try self.mode.play.tick(),
        .inventory => try self.mode.inventory.tick(),
        .explore => try self.mode.explore.tick(),
        .looking_around => try self.mode.looking_around.tick(),
    }
    try self.events.notifySubscribers();
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
        .move => |move| {
            if (self.entities.get(actor, c.Position)) |position|
                return doMove(self, actor, position, move.target, actor_speed);
        },
        .hit => |hit| if (self.entities.get(hit.target, c.Health)) |health| {
            return doHit(self, actor, hit.by_weapon, actor_speed, hit.target, health);
        },
        .open => |door| {
            try self.entities.setComponentsToEntity(door, g.entities.OpenedDoor);
        },
        .close => |door| {
            try self.entities.setComponentsToEntity(door, g.entities.ClosedDoor);
        },
        .pickup => |item| {
            const inventory = self.entities.getUnsafe(self.player, c.Inventory);
            if (self.entities.get(item, c.Pile)) |pile| {
                try self.takeFromPile(item, pile, inventory);
            } else {
                try inventory.put(item);
                try self.entities.remove(item, c.Position);
                for(self.level.entities.items, 0..) |entity, idx| {
                    if (entity.eql(item)) {
                       _ = self.level.entities.swapRemove(idx);
                        break;
                    }
                }
            }
        },
        .move_to_level => |ladder| {
            try self.movePlayerToLevel(ladder);
        },
        .go_sleep => |target| {
            self.entities.getUnsafe(target, c.EnemyState).* = .sleeping;
            try self.entities.set(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.go_sleep },
            );
        },
        .chill => |target| {
            self.entities.getUnsafe(target, c.EnemyState).* = .walking;
            try self.entities.set(
                target,
                c.Animation{ .frames = &c.Animation.FramesPresets.relax },
            );
        },
        .get_angry => |target| {
            self.entities.getUnsafe(target, c.EnemyState).* = .aggressive;
            try self.entities.set(
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

// null means that the move is completed;
// .do_nothing or any other action means that the move should be aborted, and the action handled;
fn checkCollision(self: *GameSession, actor: g.Entity, place: p.Point) ?g.Action {
    switch (self.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway)
            return null,

        .entities => |entities| {
            if (entities[2]) |entity| {
                if (self.entities.get(entity, c.Door)) |_|
                    return .{ .open = entity };

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

fn takeFromPile(self: *GameSession, item: g.Entity, pile: *c.Pile, inventory: *c.Inventory) !void {
    _ = self;
    _ = item;
    _ = pile;
    _ = inventory;
    log.err("Taking from a pile is not implemented yet", .{});
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
    try self.entities.set(enemy, c.Animation{ .frames = &c.Animation.FramesPresets.hit });
    if (actor.eql(self.player)) {
        try self.events.sendEvent(.{ .player_hit = .{ .target = enemy } });
    }
    if (enemy_health.current <= 0) {
        const is_player = enemy.eql(self.player);
        log.debug("The {s} {d} died", .{ if (is_player) "player" else "enemy", enemy.id });
        try self.level.removeEntity(enemy);
        if (is_player) {
            log.info("Player is dead. Game over.", .{});
            return error.GameOver;
        }
    }
    return actor_speed;
}

fn movePlayerToLevel(self: *GameSession, by_ladder: c.Ladder) !void {
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
        0 => try g.Levels.firstLevel(self.arena.allocator(), self, false),
        1 => try g.Levels.cave(
            self.arena.allocator(),
            self,
            self.seed + new_depth,
            new_depth,
            by_ladder,
        ),
        else => try g.Levels.catacomb(
            self.arena.allocator(),
            self,
            self.seed + new_depth,
            new_depth,
            by_ladder,
        ),
    }
    try self.mode.play.updateQuickActions(null);
    self.viewport.centeredAround(self.level.playerPosition().place);
    const event = g.events.Event{
        .entity_moved = .{
            .entity = self.player,
            .is_player = true,
            .moved_from = p.Point.init(0, 0),
            .target = .{ .new_place = self.level.playerPosition().place },
        },
    };
    try self.events.sendEvent(event);
}

pub fn getWeapon(self: *const GameSession, actor: g.Entity) ?*c.Weapon {
    if (self.entities.get(actor, c.Weapon)) |weapon| return weapon;

    if (self.entities.get(actor, c.Equipment)) |equipment|
        if (equipment.weapon) |weapon_id|
            if (self.entities.get(weapon_id, c.Weapon)) |weapon|
                return weapon;

    return null;
}

pub fn isEnemy(self: *const GameSession, entity: g.Entity) bool {
    return self.entities.get(entity, c.Health) != null;
}
