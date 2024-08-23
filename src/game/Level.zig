const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const gm = @import("game.zig");

const Level = @This();

session: *gm.GameSession,
dungeon: *gm.Dungeon,

pub fn init(session: *gm.GameSession) !Level {
    return .{
        .session = session,
        .dungeon = try gm.Dungeon.createRandom(session.game.runtime.alloc, session.game.runtime.rand),
    };
}

pub fn deinit(self: Level) void {
    self.dungeon.destroy();
}

pub fn generate(self: *Level) !void {
    const player_position = self.randomEmptyPlace() orelse unreachable;
    try self.session.components.setToEntity(self.session.player, gm.Position{ .point = player_position });

    var doors = self.dungeon.doors.keyIterator();
    while (doors.next()) |at| {
        try self.addClosedDoor(at.*);
    }

    for (0..self.session.game.runtime.rand.uintLessThan(u8, 10) + 10) |_| {
        try self.addRat();
    }
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
    self.session.entities.removeEntity(entity);
}

fn addClosedDoor(self: *Level, door_at: p.Point) !void {
    const door = try self.session.entities.newEntity();
    try self.session.components.setToEntity(door, gm.Door.closed);
    try self.session.components.setToEntity(door, gm.Position{ .point = door_at });
    try self.session.components.setToEntity(door, gm.Sprite{ .codepoint = '+' });
    try self.session.components.setToEntity(door, gm.Description{ .name = "Door" });
}

fn addRat(self: *Level) !void {
    if (self.randomEmptyPlace()) |position| {
        const rat = try self.session.entities.newEntity();
        try self.session.components.setToEntity(rat, gm.NPC{ .type = .melee });
        try self.session.components.setToEntity(rat, gm.Position{ .point = position });
        try self.session.components.setToEntity(rat, gm.Sprite{ .codepoint = 'r', .z_order = 3 });
        try self.session.components.setToEntity(rat, gm.Description{ .name = "Rat" });
        try self.session.components.setToEntity(rat, gm.Health{ .max = 10, .current = 10 });
        try self.session.components.setToEntity(rat, gm.MeleeWeapon{ .max_damage = 3, .move_points = 5 });
        try self.session.components.setToEntity(rat, gm.Speed{ .move_points = 10 });
    }
}

fn randomEmptyPlace(self: *Level) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace();
        var is_empty = true;
        for (self.session.components.getAll(gm.Position)) |position| {
            if (position.point.eql(place)) {
                is_empty = false;
            }
        }
        if (is_empty) return place;
    }
    return null;
}
