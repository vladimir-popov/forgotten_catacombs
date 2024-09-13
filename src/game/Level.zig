/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const ecs = g.ecs;
const p = g.primitives;

const BspDungeonGenerator = @import("dungeon/BspDungeonGenerator.zig");

const log = std.log.scoped(.Level);

const Level = @This();

alloc: std.mem.Allocator,
entities: std.ArrayList(g.Entity),
/// Collection of the components of the entities
components: ecs.ComponentsManager(c.Components),
dungeon: g.Dungeon,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The new new entity id
next_entity: g.Entity = 0,
/// The entity id of the player
player: g.Entity = undefined,

pub fn init(alloc: std.mem.Allocator, depth: u8) !Level {
    return .{
        .alloc = alloc,
        .entities = std.ArrayList(g.Entity).init(alloc),
        .components = try ecs.ComponentsManager(c.Components).init(alloc),
        .dungeon = try g.Dungeon.init(alloc),
        .depth = depth,
    };
}

pub fn deinit(self: *Level) void {
    self.entities.deinit();
    self.components.deinit();
    self.dungeon.deinit();
}

/// `this_ladder` - the id of the entrance when generated the lever below,
/// and the id of the exit when generated the level above.
pub fn generate(
    self: *Level,
    seed: u64,
    player: c.Components,
    this_ladder: g.Entity,
    from_ladder: ?g.Entity,
    direction: c.Ladder.Direction,
) !void {
    log.debug(
        "Generate level {s} on depth {d} with seed {d} from ladder {any} to the ladder {d} on this level",
        .{ @tagName(direction), self.depth, seed, from_ladder, this_ladder },
    );
    // This prng is used to generate entity on this level. But the dungeon should have its own prng
    // to be able to be regenerated when the player travels from level to level.
    var prng = std.Random.DefaultPrng.init(seed);
    var bspGenerator = BspDungeonGenerator{ .alloc = self.alloc };
    try bspGenerator.generator().generateDungeon(prng.random(), .{ .dungeon = &self.dungeon });

    self.next_entity = this_ladder + 1;
    var entrance_place: p.Point = undefined;
    switch (direction) {
        .down => {
            entrance_place = try self.addEntrance(prng.random(), this_ladder, from_ladder);
            try self.addExit(prng.random(), self.newEntity(), self.newEntity());
        },
        .up => {
            entrance_place = try self.addEntrance(prng.random(), self.newEntity(), self.newEntity());
            try self.addExit(prng.random(), this_ladder, from_ladder);
        },
    }

    self.player = try self.addNewEntity(player, entrance_place);
    log.debug("The Player entity id is {d}", .{self.player});

    var doors = self.dungeon.doors.keyIterator();
    while (doors.next()) |at| {
        _ = try self.addNewEntity(g.entities.ClosedDoor, at.*);
    }

    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try self.addEnemy(prng.random(), g.entities.Rat);
    }
}

/// Aggregates requests of few components for the same entities at once
pub fn query(self: *const Level) ecs.ComponentsQuery(c.Components) {
    return .{ .entities = self.entities, .components_manager = self.components };
}

pub fn playerPosition(self: *const Level) *c.Position {
    return self.components.getForEntityUnsafe(self.player, c.Position);
}

pub fn movePlayerToLadder(self: *Level, ladder: g.Entity) !void {
    log.debug("Move player to the ladder {d}", .{ladder});
    var itr = self.query().get2(c.Ladder, c.Position);
    while (itr.next()) |tuple| {
        if (tuple[1].this_ladder == ladder)
            try self.components.setToEntity(self.player, tuple[2].*);
    }
}

pub fn entityAt(self: Level, place: p.Point) ?g.Entity {
    for (self.components.arrayOf(c.Position).components.items, 0..) |position, idx| {
        if (position.point.eql(place)) {
            return self.components.arrayOf(c.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

fn initPlayer(self: *Level) !void {
    log.debug("Init player {d}", .{self.player});
    var itr = self.query().get2(c.Position, c.Ladder);
    while (itr.next()) |tuple| {
        switch (tuple[2].direction) {
            .up => {
                try self.components.setToEntity(self.player, tuple[1].*);
                break;
            },
            else => {},
        }
    }
}

fn addNewEntity(self: *Level, components: c.Components, place: p.Point) !g.Entity {
    const entity = self.newEntity();
    try self.entities.append(entity);
    try self.components.setComponentsToEntity(entity, components);
    try self.components.setToEntity(entity, c.Position{ .point = place });
    return entity;
}

fn addEnemy(self: *Level, rand: std.Random, enemy: c.Components) !void {
    if (self.randomEmptyPlace(rand, .anywhere)) |place| {
        _ = try self.addNewEntity(enemy, place);
    }
}

fn addEntrance(self: *Level, rand: std.Random, this_ladder: g.Entity, that_ladder: ?g.Entity) !p.Point {
    try self.entities.append(this_ladder);
    try self.components.setComponentsToEntity(this_ladder, g.entities.Entrance(this_ladder, that_ladder));
    const place = self.randomEmptyPlace(rand, .{ .room = self.dungeon.rooms.items[0] }) orelse
        std.debug.panic("No empty space in the first room {any}", .{self.dungeon.rooms.items[0]});
    try self.components.setToEntity(this_ladder, c.Position{ .point = place });
    std.log.debug("Created entrance {any} at {any}", .{ this_ladder, place });
    return place;
}

fn addExit(self: *Level, rand: std.Random, this_ladder: g.Entity, that_ladder: ?g.Entity) !void {
    try self.entities.append(this_ladder);
    try self.components.setComponentsToEntity(this_ladder, g.entities.Exit(this_ladder, that_ladder));
    const place = self.randomEmptyPlace(rand, .{ .room = self.dungeon.rooms.getLast() }) orelse
        std.debug.panic("No empty space in the last room {any}", .{self.dungeon.rooms.getLast()});
    try self.components.setToEntity(this_ladder, c.Position{ .point = place });
    std.log.debug("Created exit {any} at {any}", .{ this_ladder, place });
}

inline fn newEntity(self: *Level) g.Entity {
    const entity = self.next_entity;
    self.next_entity += 1;
    return entity;
}

pub fn removeEntity(self: *Level, entity: g.Entity) !void {
    try self.components.removeAllForEntity(entity);
    // this is rare operation, and O(n) here is not as bad, as good the iteration over elements
    // in array in all other cases
    if (std.mem.indexOfScalar(g.Entity, self.entities.items, entity)) |idx|
        _ = self.entities.swapRemove(idx);
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
        var itr = self.query().get(c.Position);
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
