const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const game = @import("game.zig");

const log = std.log.scoped(.GameSession);

const Self = @This();

const System = *const fn (game: *Self) anyerror!void;

pub const Timers = enum { tick };

pub const QuickAction = union(enum) {
    hit: game.Entity,
    open,
};

runtime: game.AnyRuntime,
entities: ecs.EntitiesManager,
components: ecs.ComponentsManager(game.Components),
query: ecs.ComponentsQuery(game.Components) = undefined,
screen: game.Screen,
timers: []c_uint,
systems: std.ArrayList(System),
dungeon: *game.Dungeon,
player: game.Entity = undefined,
quick_actions: std.ArrayList(QuickAction),

pub fn create(runtime: game.AnyRuntime) !*Self {
    const session = try runtime.alloc.create(Self);
    session.* = .{
        .runtime = runtime,
        .screen = game.Screen.init(game.DISPLAY_DUNG_ROWS, game.DISPLAY_DUNG_COLS, game.Dungeon.Region),
        .timers = try runtime.alloc.alloc(c_uint, std.meta.tags(Timers).len),
        .entities = try ecs.EntitiesManager.init(runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(runtime.alloc),
        .systems = std.ArrayList(System).init(runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
        .quick_actions = std.ArrayList(QuickAction).init(runtime.alloc),
    };
    session.query = .{ .entities = &session.entities, .components = &session.components };
    const player_and_position = try initLevel(session.dungeon, &session.entities, &session.components);
    session.player = player_and_position[0];
    session.screen.centeredAround(player_and_position[1]);

    // Initialize systems:
    try session.systems.append(game.handleInput);
    try session.systems.append(game.handleMove);
    try session.systems.append(game.handleCollisions);
    try session.systems.append(game.handleDamage);
    try session.systems.append(game.render);
    session.setTimer(.tick, 0);

    return session;
}

pub fn destroy(self: *Self) void {
    self.entities.deinit();
    self.components.deinit();
    self.systems.deinit();
    self.dungeon.destroy();
    self.quick_actions.deinit();
    self.runtime.alloc.free(self.timers);
    self.runtime.alloc.destroy(self);
}

pub inline fn getTimer(self: Self, t: Timers) c_uint {
    return self.timers[@intFromEnum(t)];
}

pub inline fn setTimer(self: *Self, t: Timers, value: c_uint) void {
    self.timers[@intFromEnum(t)] = value;
}

pub fn tick(self: *Self) anyerror!void {
    const now = self.runtime.currentMillis();
    const delay = now - self.getTimer(.tick);
    self.setTimer(.tick, now);
    _ = delay;
    for (self.systems.items) |system| {
        try system(self);
    }
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
