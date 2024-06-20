const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const game = @import("game.zig");

const Self = @This();

const System = *const fn (game: *Self) anyerror!void;

pub const Timers = enum { key_pressed };

runtime: game.AnyRuntime,
screen: game.Screen,
timers: []i64,
entities: ecs.EntitiesManager,
components: ecs.ComponentsManager(game.Components),
systems: std.ArrayList(System),
dungeon: *game.Dungeon,
player: game.Entity = undefined,

pub fn create(runtime: game.AnyRuntime) !*Self {
    const session = try runtime.alloc.create(Self);
    session.* = .{
        .runtime = runtime,
        .screen = game.Screen.init(game.DISPLAY_DUNG_ROWS, game.DISPLAY_DUNG_COLS, game.Dungeon.Region),
        .timers = try runtime.alloc.alloc(i64, std.meta.tags(Timers).len),
        .entities = try ecs.EntitiesManager.init(runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(runtime.alloc),
        .systems = std.ArrayList(System).init(runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
    };
    const player_position = session.dungeon.randomPlaceInRoom();
    session.screen.centeredAround(player_position);

    session.player = try initPlayer(&session.entities, &session.components, player_position);

    // Initialize systems:
    try session.systems.append(game.handleInput);
    try session.systems.append(game.handleMove);
    try session.systems.append(game.render);

    return session;
}

pub fn destroy(self: *Self) void {
    self.entities.deinit();
    self.components.deinit();
    self.systems.deinit();
    self.dungeon.destroy();
    self.runtime.alloc.free(self.timers);
    self.runtime.alloc.destroy(self);
}

pub inline fn timer(self: Self, t: Timers) *i64 {
    return &self.timers[@intFromEnum(t)];
}

pub fn tick(self: *Self) anyerror!void {
    for (self.systems.items) |system| {
        try system(self);
    }
}

pub fn Query2(comptime Cmp1: type, Cmp2: type) type {
    return struct {
        const Q2 = @This();
        session: *Self,
        entities: ecs.EntitiesManager.EntitiesIterator,

        pub fn next(self: *Q2) ?struct { *game.Entity, *Cmp1, *Cmp2 } {
            if (self.entities.next()) |entity| {
                if (self.session.components.getForEntity(entity.*, Cmp1)) |c1| {
                    if (self.session.components.getForEntity(entity.*, Cmp2)) |c2| {
                        return .{ entity, c1, c2 };
                    }
                }
            }
            return null;
        }
    };
}

pub fn queryComponents2(self: *Self, comptime Cmp1: type, Cmp2: type) Query2(Cmp1, Cmp2) {
    return .{ .session = self, .entities = self.entities.iterator() };
}

pub fn initPlayer(
    entities: *ecs.EntitiesManager,
    components: *ecs.ComponentsManager(game.Components),
    init_position: p.Point,
) !game.Entity {
    const player = try entities.newEntity();
    try components.addToEntity(player, game.Position{ .point = init_position });
    try components.addToEntity(player, game.Move{});
    try components.addToEntity(player, game.Sprite{ .letter = "@" });
    try components.addToEntity(player, game.Health{ .health = 100 });
    return player;
}
