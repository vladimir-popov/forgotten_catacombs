const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const ecs = @import("ecs");
const gm = @import("game.zig");

const log = std.log.scoped(.Level);

const Level = @This();

player: gm.Entity,
entities_provider: ecs.EntitiesProvider,
entities: std.ArrayList(gm.Entity),
/// Collection of the components of the entities
components: ecs.ComponentsManager(gm.Components),
dungeon: *gm.Dungeon,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,

pub fn generate(
    alloc: std.mem.Allocator,
    session_seed: u64,
    player: gm.Entity,
    entities_provider: ecs.EntitiesProvider,
    depth: u8,
    this_ladder: gm.Entity,
    from_ladder: ?gm.Entity,
    direction: gm.Ladder.Direction,
) !Level {
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any} to the ladder {d} on this level",
        .{ @tagName(direction), depth, session_seed + depth, from_ladder, this_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(session_seed + depth);
    var self = Level{
        .player = player,
        .entities_provider = entities_provider,
        .depth = depth,
        .dungeon = try gm.Dungeon.createRandom(alloc, session_seed + depth),
        .entities = std.ArrayList(gm.Entity).init(alloc),
        .components = try ecs.ComponentsManager(gm.Components).init(alloc),
    };

    try self.entities.append(self.player);

    var doors = self.dungeon.doors.keyIterator();
    while (doors.next()) |at| {
        try self.addClosedDoor(at.*);
    }

    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try self.addRat(prng.random());
    }

    switch (direction) {
        .up => {
            try self.addEntrance(prng.random(), self.newEntity(), self.newEntity());
            try self.addExit(prng.random(), this_ladder, from_ladder);
        },
        .down => {
            try self.addEntrance(prng.random(), this_ladder, from_ladder);
            if (depth == 0) try self.initPlayer();
            try self.addExit(prng.random(), self.newEntity(), self.newEntity());
        },
    }
    return self;
}

pub fn deinit(self: *Level) void {
    self.dungeon.destroy();
    self.entities.deinit();
    self.components.deinit();
}

/// Aggregates requests of few components for the same entities at once
pub fn query(self: *const Level) ecs.ComponentsQuery(gm.Components) {
    return .{ .entities = self.entities, .components_manager = self.components };
}

pub fn playerPosition(self: *const Level) *gm.Position {
    return self.components.getForEntityUnsafe(self.player, gm.Position);
}

pub fn movePlayerToLadder(self: *Level, ladder: gm.Entity) !void {
    log.debug("Move player to the ladder {d}", .{ladder});
    var itr = self.query().get2(gm.Ladder, gm.Position);
    while (itr.next()) |tuple| {
        if (tuple[1].this_ladder == ladder)
            try self.components.setToEntity(self.player, tuple[2].*);
    }
}

pub fn entityAt(self: Level, place: p.Point) ?gm.Entity {
    for (self.components.arrayOf(gm.Position).components.items, 0..) |position, idx| {
        if (position.point.eql(place)) {
            return self.components.arrayOf(gm.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

inline fn newEntity(self: *Level) gm.Entity {
    return self.entities_provider.newEntity();
}

pub fn removeEntity(self: *Level, entity: gm.Entity) !void {
    try self.components.removeAllForEntity(entity);
    // this is rare operation, and O(n) here is not as bad, as good the iteration over elements
    // in array in all other cases
    if (std.mem.indexOfScalar(gm.Entity, self.entities.items, entity)) |idx|
        _ = self.entities.swapRemove(idx);
}

fn initPlayer(self: *Level) !void {
    log.debug("Init player {d}", .{self.player});
    var itr = self.query().get2(gm.Position, gm.Ladder);
    while (itr.next()) |tuple| {
        switch (tuple[2].direction) {
            .up => {
                try self.components.setToEntity(self.player, tuple[1].*);
                break;
            },
            else => {},
        }
    }
    try self.components.setToEntity(self.player, gm.Sprite{ .codepoint = '@', .z_order = 3 });
    try self.components.setToEntity(self.player, gm.Description{ .name = "You" });
    try self.components.setToEntity(self.player, gm.Health{ .max = 100, .current = 30 });
    try self.components.setToEntity(self.player, gm.MeleeWeapon{ .max_damage = 3, .move_points = 10 });
    try self.components.setToEntity(self.player, gm.Speed{ .move_points = 10 });
}

fn addEntrance(self: *Level, rand: std.Random, this_ladder: gm.Entity, that_ladder: ?gm.Entity) !void {
    try self.entities.append(this_ladder);
    const ladder = gm.Ladder{ .this_ladder = this_ladder, .that_ladder = that_ladder, .direction = .up };
    try self.components.setToEntity(this_ladder, ladder);
    try self.components.setToEntity(this_ladder, gm.Description{ .name = "Ladder up" });
    try self.components.setToEntity(this_ladder, gm.Sprite{ .codepoint = '<', .z_order = 2 });
    const position = gm.Position{
        .point = self.randomEmptyPlace(rand, .{ .room = self.dungeon.rooms.items[0] }) orelse
            std.debug.panic("No empty space in the first room {any}", .{self.dungeon.rooms.items[0]}),
    };
    try self.components.setToEntity(this_ladder, position);
    std.log.debug("Created entrance {any} at {any}", .{ ladder, position });
}

fn addExit(self: *Level, rand: std.Random, this_ladder: gm.Entity, that_ladder: ?gm.Entity) !void {
    try self.entities.append(this_ladder);
    const ladder = gm.Ladder{ .this_ladder = this_ladder, .that_ladder = that_ladder, .direction = .down };
    try self.components.setToEntity(this_ladder, ladder);
    try self.components.setToEntity(this_ladder, gm.Description{ .name = "Ladder down" });
    try self.components.setToEntity(this_ladder, gm.Sprite{ .codepoint = '>', .z_order = 2 });
    const position = gm.Position{
        .point = self.randomEmptyPlace(rand, .{ .room = self.dungeon.rooms.getLast() }) orelse
            std.debug.panic("No empty space in the last room {any}", .{self.dungeon.rooms.getLast()}),
    };
    try self.components.setToEntity(this_ladder, position);
}

fn addClosedDoor(self: *Level, door_at: p.Point) !void {
    const door = self.newEntity();
    try self.entities.append(door);
    try self.components.setToEntity(door, gm.Door.closed);
    try self.components.setToEntity(door, gm.Position{ .point = door_at });
    try self.components.setToEntity(door, gm.Sprite{ .codepoint = '+' });
    try self.components.setToEntity(door, gm.Description{ .name = "Door" });
}

fn addRat(self: *Level, rand: std.Random) !void {
    if (self.randomEmptyPlace(rand, .anywhere)) |position| {
        const rat = self.newEntity();
        try self.entities.append(rat);
        try self.components.setToEntity(rat, gm.NPC{ .type = .melee });
        try self.components.setToEntity(rat, gm.Position{ .point = position });
        try self.components.setToEntity(rat, gm.Sprite{ .codepoint = 'r', .z_order = 3 });
        try self.components.setToEntity(rat, gm.Description{ .name = "Rat" });
        try self.components.setToEntity(rat, gm.Health{ .max = 10, .current = 10 });
        try self.components.setToEntity(rat, gm.MeleeWeapon{ .max_damage = 3, .move_points = 5 });
        try self.components.setToEntity(rat, gm.Speed{ .move_points = 10 });
    }
}

const PlaceClarification = union(enum) {
    anywhere,
    room: p.Region,
};

fn randomEmptyPlace(self: *Level, rand: std.Random, clarification: PlaceClarification) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = switch (clarification) {
            .anywhere => self.randomPlace(rand),
            .room => |room| randomPlaceInRoom(room, rand),
        };
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

fn randomPlace(self: *Level, rand: std.Random) p.Point {
    if (rand.uintLessThan(u8, 5) > 3 and self.dungeon.passages.items.len > 0) {
        const passage = self.dungeon.passages.items[rand.uintLessThan(usize, self.dungeon.passages.items.len)];
        return passage.randomPlace(rand);
    } else {
        const room = self.dungeon.rooms.items[rand.uintLessThan(usize, self.dungeon.rooms.items.len)];
        return randomPlaceInRoom(room, rand);
    }
}

fn randomPlaceInRoom(room: p.Region, rand: std.Random) p.Point {
    return .{
        .row = room.top_left.row + rand.uintLessThan(u8, room.rows - 2) + 1,
        .col = room.top_left.col + rand.uintLessThan(u8, room.cols - 2) + 1,
    };
}
