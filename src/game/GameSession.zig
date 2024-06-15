const std = @import("std");
const ecs = @import("ecs");
const game = @import("game.zig");

const Self = @This();

const System = *const fn (game: *Self) anyerror!void;

pub const Timers = enum { input_system };

runtime: game.AnyRuntime,
screen: game.Screen,
timers: []i64,
entities: std.AutoHashMap(game.Entity, void),
components: ecs.ComponentsManager(game.Components),
systems: std.ArrayList(System),
dungeon: *game.Dungeon,
next_entity: game.Entity = 0,
player: game.Entity = undefined,

pub fn create(runtime: game.AnyRuntime) !*Self {
    const session = try runtime.alloc.create(Self);
    session.* = .{
        .runtime = runtime,
        .screen = game.Screen.init(game.DISPLAY_ROWS, game.DISPLAY_COLS, game.Dungeon.Region),
        .timers = try runtime.alloc.alloc(i64, std.meta.tags(Timers).len),
        .entities = std.AutoHashMap(game.Entity, void).init(runtime.alloc),
        .components = try ecs.ComponentsManager(game.Components).init(runtime.alloc),
        .systems = std.ArrayList(System).init(runtime.alloc),
        .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
    };
    const player_position = session.dungeon.findRandomPlaceForPlayer();
    session.screen.centeredAround(player_position);

    session.player = try session.newEntity();
    try session.components.addToEntity(session.player, game.Position{ .point = player_position });
    try session.components.addToEntity(session.player, game.Move{});
    try session.components.addToEntity(session.player, game.Sprite{ .letter = "@" });

    // Initialize systems:
    try session.systems.append(game.InputSystem.handleInput);
    try session.systems.append(game.MovementSystem.handleMove);
    try session.systems.append(game.RenderSystem.render);

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

/// Generates an unique id for the new entity, puts it to the inner storage,
/// and then returns as the result. The id is unique for whole life circle of
/// this manager.
fn newEntity(self: *Self) !game.Entity {
    const entity = self.next_entity;
    self.next_entity += 1;
    try self.entities.put(entity, {});
    return entity;
}

/// Removes all components of the entity and it self from the inner storage.
fn removeEntity(self: *Self, entity: game.Entity) void {
    self.components.removeAllForEntity(entity);
    self.entities.remove(entity);
}

pub fn Query2(comptime Cmp1: type, Cmp2: type) type {
    return struct {
        const Q2 = @This();
        session: *Self,
        entities: std.AutoHashMap(game.Entity, void).KeyIterator,

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
    return .{ .session = self, .entities = self.entities.keyIterator() };
}
