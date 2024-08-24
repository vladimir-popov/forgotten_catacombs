const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const gm = @import("game.zig");

const Level = @This();

session: *gm.GameSession,
entities: std.ArrayList(gm.Entity),
dungeon: *gm.Dungeon,
/// The depth of the current level. The session.seed + depth is unique seed for the level.
depth: u8,

pub fn generate(session: *gm.GameSession, depth: u8) !Level {
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(session.seed + depth);
    var self = Level{
        .session = session,
        .depth = depth,
        .dungeon = try gm.Dungeon.createRandom(session.game.runtime.alloc, session.seed + depth),
        .entities = std.ArrayList(gm.Entity).init(session.game.runtime.alloc),
    };
    try self.entities.append(self.session.player);
    const player_position = self.randomEmptyPlace(prng.random()) orelse unreachable;
    try self.session.components.setToEntity(self.session.player, gm.Position{ .point = player_position });

    var doors = self.dungeon.doors.keyIterator();
    while (doors.next()) |at| {
        try self.addClosedDoor(at.*);
    }

    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try self.addRat(prng.random());
    }
    return self;
}

pub fn deinit(self: *Level) void {
    self.dungeon.destroy();
    self.entities.deinit();
}

/// Aggregates requests of few components for the same entities at once
pub fn query(self: *const Level) ecs.ComponentsQuery(gm.Components) {
    return .{ .entities = self.entities, .components_manager = self.session.components };
}

pub fn entityAt(self: Level, place: p.Point) ?gm.Entity {
    for (self.session.components.arrayOf(gm.Position).components.items, 0..) |position, idx| {
        if (position.point.eql(place)) {
            return self.session.components.arrayOf(gm.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

pub fn removeEntity(self: *Level, entity: gm.Entity) !void {
    try self.session.components.removeAllForEntity(entity);
    _ = self.entities.swapRemove(entity);
}

fn addClosedDoor(self: *Level, door_at: p.Point) !void {
    const door = try self.session.newEntity();
    try self.entities.append(door);
    try self.session.components.setToEntity(door, gm.Door.closed);
    try self.session.components.setToEntity(door, gm.Position{ .point = door_at });
    try self.session.components.setToEntity(door, gm.Sprite{ .codepoint = '+' });
    try self.session.components.setToEntity(door, gm.Description{ .name = "Door" });
}

fn addRat(self: *Level, rand: std.Random) !void {
    if (self.randomEmptyPlace(rand)) |position| {
        const rat = try self.session.newEntity();
        try self.entities.append(rat);
        try self.session.components.setToEntity(rat, gm.NPC{ .type = .melee });
        try self.session.components.setToEntity(rat, gm.Position{ .point = position });
        try self.session.components.setToEntity(rat, gm.Sprite{ .codepoint = 'r', .z_order = 3 });
        try self.session.components.setToEntity(rat, gm.Description{ .name = "Rat" });
        try self.session.components.setToEntity(rat, gm.Health{ .max = 10, .current = 10 });
        try self.session.components.setToEntity(rat, gm.MeleeWeapon{ .max_damage = 3, .move_points = 5 });
        try self.session.components.setToEntity(rat, gm.Speed{ .move_points = 10 });
    }
}

fn randomEmptyPlace(self: *Level, rand: std.Random) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace(rand);
        var is_empty = true;
        var itr = self.query().get(gm.Position);
        while (itr.next()) |tuple| {
            if (tuple[1].point.eql(place)) {
                is_empty = false;
            }
        }
        if (is_empty) return place;
    }
    return null;
}
