/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const ecs = g.ecs;
const p = g.primitives;

const BspDungeonGenerator = @import("dungeon/BspDungeonGenerator.zig");

const log = std.log.scoped(.level);

const Error = error{RoomWasNotFound};

const Level = @This();

alloc: std.mem.Allocator,
entities: std.ArrayList(g.Entity),
/// Collection of the components of the entities
components: ecs.ComponentsManager(c.Components),
dungeon: g.Dungeon,
map: g.LevelMap,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The new new entity id
next_entity: g.Entity = 0,
/// The entity id of the player
player: g.Entity = undefined,
player_placement: *const g.Dungeon.Placement = undefined,

pub fn init(alloc: std.mem.Allocator, depth: u8) !Level {
    return .{
        .alloc = alloc,
        .entities = std.ArrayList(g.Entity).init(alloc),
        .components = try ecs.ComponentsManager(c.Components).init(alloc),
        .dungeon = try g.Dungeon.init(alloc),
        .map = try g.LevelMap.init(alloc),
        .depth = depth,
    };
}

pub fn deinit(self: *Level) void {
    self.entities.deinit();
    self.components.deinit();
    self.dungeon.deinit();
    self.map.deinit();
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
    try bspGenerator.generateDungeon(prng.random(), &self.dungeon);
    log.debug("The dungeon has been generated", .{});

    self.next_entity = this_ladder + 1;
    var entrance_place: struct { *const g.Dungeon.Placement, p.Point } = undefined;
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

    self.player = try self.addNewEntity(player, entrance_place[1]);
    try self.setPlacementWithPlayer(entrance_place[0]);
    log.debug("The Player entity id is {d}", .{self.player});

    var doors = self.dungeon.doorways.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.addNewEntity(g.entities.ClosedDoor, entry.key_ptr.*);
    }

    for (0..prng.random().uintLessThan(u8, 10) + 10) |_| {
        try self.addEnemy(prng.random(), g.entities.Rat);
    }
}

pub fn regenerate(
    self: *Level,
    seed: u64,
    depth: u8,
    this_ladder: g.Entity,
    from_ladder: ?g.Entity,
    direction: c.Ladder.Direction,
) !void {
    const player = try self.components.entityToStruct(self.player);
    self.entities.clearRetainingCapacity();
    self.components.clearRetainingCapacity();
    try self.dungeon.clearRetainingCapacity();
    self.map.clearRetainingCapacity();
    self.depth = depth;
    try self.generate(seed, player, this_ladder, from_ladder, direction);
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

pub fn isVisible(self: Level, place: p.Point) g.render.Visibility {
    if (self.player_placement.contains(place))
        return .visible;

    var doorways = self.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (self.dungeon.doorways.getPtr(door_place.*)) |doorway| {
            // skip the neighbor if the door between is closed
            if (self.components.getForEntityUnsafe(doorway.door_id, c.Door).state == .closed)
                continue;

            if (doorway.oppositePlacement(self.player_placement).contains(place))
                return .visible;
        }
    }
    if (self.map.visited_places.isSet(place.row, place.col))
        return .known;

    return .invisible;
}

pub fn entityMovedSubscriber(self: *Level) g.events.Subscriber(g.events.EntityMoved) {
    return .{ .context = self, .onEvent = updatePlacement };
}

fn updatePlacement(ptr: *anyopaque, event: g.events.EntityMoved) !void {
    if (!event.is_player) return;

    const self: *Level = @ptrCast(@alignCast(ptr));

    if (self.player_placement.contains(event.moved_to)) return;

    if (self.dungeon.doorways.getPtr(event.moved_from)) |doorway| {
        const placement = doorway.oppositePlacement(self.player_placement);
        std.debug.assert(placement.contains(event.moved_to));
        try self.setPlacementWithPlayer(placement);
    }
}

pub fn setPlacementWithPlayer(self: *Level, placement: *const g.Dungeon.Placement) !void {
    log.debug("New placement with player: {any}", .{placement});
    self.player_placement = placement;
    try self.map.addVisitedPlacement(placement);
    var doorways = self.player_placement.doorways();
    while (doorways.next()) |door_place| {
        if (self.dungeon.doorways.getPtr(door_place.*)) |doorway| {
            if (self.components.getForEntity(doorway.door_id, c.Door)) |door| if (door.state == .opened)
                try self.map.addVisitedPlacement(doorway.oppositePlacement(self.player_placement));
        }
    }
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

fn addEntrance(
    self: *Level,
    rand: std.Random,
    this_ladder: g.Entity,
    that_ladder: ?g.Entity,
) !struct { *const g.Dungeon.Placement, p.Point } {
    try self.entities.append(this_ladder);
    try self.components.setComponentsToEntity(this_ladder, g.entities.Entrance(this_ladder, that_ladder));
    const firstRoom = try getFirstRoom(self.dungeon);
    const place = self.randomEmptyPlace(rand, .{ .region = firstRoom.room.region }) orelse
        std.debug.panic("No empty space in the first room {any}", .{firstRoom});
    try self.components.setToEntity(this_ladder, c.Position{ .point = place });
    std.log.debug("Created entrance {any} at {any}", .{ this_ladder, place });
    return .{ firstRoom, place };
}

fn addExit(self: *Level, rand: std.Random, this_ladder: g.Entity, that_ladder: ?g.Entity) !void {
    try self.entities.append(this_ladder);
    try self.components.setComponentsToEntity(this_ladder, g.entities.Exit(this_ladder, that_ladder));
    const lastRoom = try getLastRoom(self.dungeon);
    const place = self.randomEmptyPlace(rand, .{ .region = lastRoom.room.region }) orelse
        std.debug.panic("No empty space in the last room {any}", .{lastRoom});
    try self.components.setToEntity(this_ladder, c.Position{ .point = place });
    std.log.debug("Created exit {any} at {any}", .{ this_ladder, place });
}

fn getFirstRoom(dungeon: g.Dungeon) Error!*const g.Dungeon.Placement {
    for (dungeon.placements.items) |placement| {
        switch (placement.*) {
            .room => return placement,
            else => {},
        }
    }
    return Error.RoomWasNotFound;
}

fn getLastRoom(dungeon: g.Dungeon) Error!*const g.Dungeon.Placement {
    var i: usize = dungeon.placements.items.len - 1;
    while (i >= 0) : (i -= 1) {
        switch (dungeon.placements.items[i].*) {
            .room => return dungeon.placements.items[i],
            else => {},
        }
    }
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

const PlaceClarification = union(enum) { anywhere, region: p.Region };

fn randomEmptyPlace(self: *Level, rand: std.Random, clarification: PlaceClarification) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = switch (clarification) {
            .anywhere => self.randomPlace(rand),
            .region => |region| randomPlaceInRegion(region, rand),
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
    const placement = self.dungeon.placements.items[rand.uintLessThan(usize, self.dungeon.placements.items.len)];
    switch (placement.*) {
        .room => |room| return randomPlaceInRegion(room.region, rand),
        .passage => |passage| return passage.randomPlace(rand),
    }
}

fn randomPlaceInRegion(region: p.Region, rand: std.Random) p.Point {
    return .{
        .row = region.top_left.row + rand.uintLessThan(u8, region.rows - 2) + 1,
        .col = region.top_left.col + rand.uintLessThan(u8, region.cols - 2) + 1,
    };
}
