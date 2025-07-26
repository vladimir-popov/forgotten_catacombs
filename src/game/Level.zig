/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const cp = g.codepoints;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.level);

const Self = @This();

pub const Cell = union(enum) {
    landscape: d.Dungeon.Cell,
    entities: [3]?g.Entity,
};

pub const DijkstraMapRegion = p.Region{ .top_left = .{ .row = 1, .col = 1 }, .rows = 12, .cols = 25 };

arena: std.heap.ArenaAllocator,
registry: *g.Registry,
player: g.Entity = undefined,
/// The list of the entities belong to this level.
/// Used to cleanup global registry on moving from the level.
/// The player doesn't belong to any particular level and should not be presented here.
entities: std.ArrayListUnmanaged(g.Entity),
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8 = undefined,
dungeon: d.Dungeon = undefined,
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility = undefined,
/// Already visited places in the dungeon.
visited_places: []std.DynamicBitSetUnmanaged = undefined,
/// All static objects (doors, ladders, items) met previously.
remembered_objects: std.AutoHashMapUnmanaged(p.Point, g.Entity),
/// The placement where the player right now. It's used for optimization.
player_placement: d.Placement = undefined,
/// Dijkstra Map of direction to the player. Used to find a path to the player.
dijkstra_map: u.DijkstraMap.VectorsMap,

/// Initializes an arena to store everything inside the level.
pub fn preInit(
    alloc: std.mem.Allocator,
    registry: *g.Registry,
) Self {
    return .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .registry = registry,
        .entities = .empty,
        .remembered_objects = .empty,
        .dijkstra_map = .empty,
    };
}

pub fn deinit(self: *Self) void {
    log.debug("Deinit level on depth {d}", .{self.depth});
    self.arena.deinit();
}

/// Resets the inner arena, and sets up all containers to the empty state.
/// Sets up the level to the preinited state.
pub fn reset(self: *Self) void {
    log.debug("Reset level on depth {d}", .{self.depth});
    std.debug.assert(self.arena.reset(.retain_capacity));
    self.entities = .empty;
    self.remembered_objects = .empty;
    self.dijkstra_map = .empty;
}

/// Generates with the passed seed and sets up a dungeon to the preinited level.
/// This is the first step in loading a level.
pub fn initWithEmptyDungeon(
    self: *Self,
    player: g.Entity,
    depth: u8,
    seed: u64,
) !void {
    const dungeon = try generateDungeon(&self.arena, depth, seed) orelse {
        log.err("A dungeon was not generate from the saved seed {d}", .{seed});
        return error.BrokenSeed;
    };
    try self.setupDungeon(depth, dungeon, player);
}

/// Sets up the dungeon to the level, and initializes the inner state according to the dungeon.
/// The level should be preinitialized before run this method.
fn setupDungeon(
    self: *Self,
    depth: u8,
    dungeon: d.Dungeon,
    player: g.Entity,
) !void {
    log.debug(
        "Setting up a dungeon with type {s} to the level on depth {d}. Player id is {d}",
        .{ @tagName(dungeon.type), depth, player.id },
    );

    const alloc = self.arena.allocator();

    self.depth = depth;
    self.player = player;
    self.dungeon = dungeon;
    self.visibility_strategy = switch (dungeon.type) {
        .first_location => g.visibility.showTheCurrentPlacement,
        .cave => g.visibility.showInRadiusOfSourceOfLight,
        .catacomb => if (depth < 3)
            g.visibility.showTheCurrentPlacement
        else
            g.visibility.showTheCurrentPlacementInLight,
    };
    self.visited_places = try alloc.alloc(std.DynamicBitSetUnmanaged, dungeon.rows);

    for (0..self.dungeon.rows) |r0| {
        self.visited_places[r0] = try std.DynamicBitSetUnmanaged.initEmpty(alloc, self.dungeon.cols);
    }
}

/// Completely initializes a preinited level as the first location in the game.
pub fn initAsFirstLevel(
    self: *Self,
    player: g.Entity,
) !void {
    log.debug("Start creating the first level.", .{});

    try self.initWithEmptyDungeon(player, 0, 0);
    const arena_alloc = self.arena.allocator();

    // Add wharf
    var entity = try self.registry.addNewEntity(.{
        .description = .{ .preset = .wharf },
        .sprite = .{ .codepoint = cp.ladder_up },
        .position = .{ .place = self.dungeon.entrance, .zorder = .floor },
    });
    try self.entities.append(arena_alloc, entity);

    // Add the ladder leads to the bottom dungeons:
    entity = self.registry.newEntity();
    try self.registry.setComponentsToEntity(entity, .{
        .ladder = .{
            .direction = .down,
            .id = entity,
            .target_ladder = self.registry.newEntity(),
        },
        .description = .{ .preset = .ladder_down },
        .sprite = .{ .codepoint = cp.ladder_down },
        .position = .{ .place = self.dungeon.exit, .zorder = .floor },
    });
    try self.entities.append(arena_alloc, entity);

    // Add the trader
    var shop = try c.Shop.empty(self.registry.allocator(), 1.5, 200);
    try shop.items.add(try self.registry.addNewEntity(g.entities.Club));
    entity = try self.registry.addNewEntity(.{
        .position = .{ .place = d.FirstLocation.trader_place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .traider },
        .shop = shop,
    });
    try self.entities.append(arena_alloc, entity);

    // Add the scientist
    entity = try self.registry.addNewEntity(.{
        .position = .{ .place = d.FirstLocation.scientist_place, .zorder = .obstacle },
        .sprite = .{ .codepoint = cp.human },
        .description = .{ .preset = .scientist },
    });
    try self.entities.append(arena_alloc, entity);

    // Add the teleport
    entity = try self.registry.addNewEntity(g.entities.teleport(d.FirstLocation.teleport_place));
    try self.entities.append(arena_alloc, entity);

    // Add doors
    var doors = self.dungeon.doorways.?.iterator();
    while (doors.next()) |entry| {
        entry.value_ptr.door_id = try self.registry.addNewEntity(g.entities.closedDoor(entry.key_ptr.*));
        try self.entities.append(arena_alloc, entry.value_ptr.door_id);
        log.debug(
            "For the doorway on {any} added closed door with id {d}",
            .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
        );
    }
    try self.completeInitialization(.down);
}

/// Tries to generate a new level with passed seed.
/// The level should be preinited before run this method.
/// In successful case the level becomes completely initialized and true is returned.
/// Otherwise the inner arena is cleaned up and false is returned.
pub fn tryGenerateNew(
    self: *Self,
    player: g.Entity,
    depth: u8,
    from_ladder: c.Ladder,
    seed: u64,
) !bool {
    const dungeon: d.Dungeon = (try generateDungeon(&self.arena, depth, seed)) orelse {
        self.reset();
        return false;
    };
    log.debug("A {s} has been generated on depth {d}.", .{ @tagName(dungeon.type), depth });

    const arena_alloc = self.arena.allocator();

    try self.setupDungeon(depth, dungeon, player);

    const init_place = switch (from_ladder.direction) {
        .down => self.dungeon.entrance,
        .up => self.dungeon.exit,
    };
    const exit_place = switch (from_ladder.direction) {
        .up => self.dungeon.entrance,
        .down => self.dungeon.exit,
    };
    // Add ladder by which the player has come to this level
    try self.addLadder(from_ladder.inverted(), init_place);

    // Add ladder to the next level
    try self.addLadder(.{
        .direction = from_ladder.direction,
        .id = self.registry.newEntity(),
        .target_ladder = self.registry.newEntity(),
    }, exit_place);

    // Add enemies
    var prng = std.Random.DefaultPrng.init(dungeon.seed);
    const rand = prng.random();
    for (0..rand.uintLessThan(u8, 10) + 10) |_| {
        if (self.randomEmptyPlace(rand)) |place| {
            try self.addEnemy(rand, g.entities.rat(place));
        }
    }

    // Add doors
    if (self.dungeon.doorways) |doorways| {
        var doors = doorways.iterator();
        while (doors.next()) |entry| {
            entry.value_ptr.door_id = try self.registry.addNewEntity(g.entities.closedDoor(entry.key_ptr.*));
            try self.entities.append(arena_alloc, entry.value_ptr.door_id);
            log.debug(
                "For the doorway on {any} added closed door with id {d}",
                .{ entry.key_ptr.*, entry.value_ptr.door_id.id },
            );
        }
    }
    try self.completeInitialization(from_ladder.direction);
    return true;
}

/// Sets up a position for the player if the direction is provided, and remembers the placement with the player.
/// This is the final step of the initialization process.
pub fn completeInitialization(self: *Self, moving_direction: ?c.Ladder.Direction) !void {
    if (moving_direction) |direction| {
        const init_place = switch (direction) {
            .down => self.dungeon.entrance,
            .up => self.dungeon.exit,
        };
        log.debug("Move the player to the ladder in direction {s}.", .{@tagName(direction)});
        try self.registry.set(self.player, c.Position{ .place = init_place, .zorder = .obstacle });
    }
    self.player_placement = self.dungeon.placementWith(self.playerPosition().place).?;

    log.debug(
        "The level is completed. Depth {d}; seed {d}; type {s}; player {d}, its position {any}",
        .{ self.depth, self.dungeon.seed, @tagName(self.dungeon.type), self.player.id, self.playerPosition().place },
    );
}

fn generateDungeon(arena: *std.heap.ArenaAllocator, depth: u8, seed: u64) !?d.Dungeon {
    return if (depth == 0)
        try d.FirstLocation.generateDungeon(arena)
    else if (depth < 3)
        try d.Cave.generateDungeon(arena, .{}, seed)
    else
        try d.Catacomb.generateDungeon(arena, .{}, seed);
}

pub fn isVisited(self: Self, place: p.Point) bool {
    if (place.row > self.dungeon.rows or place.col > self.dungeon.cols) return false;
    return self.visited_places[place.row - 1].isSet(place.col - 1);
}

pub fn addVisitedPlace(self: *Self, visited_place: p.Point) !void {
    if (visited_place.row > self.dungeon.rows or visited_place.col > self.dungeon.cols) return;
    self.visited_places[visited_place.row - 1].set(visited_place.col - 1);
}

pub fn rememberObject(self: *Self, entity: g.Entity, place: p.Point) !void {
    log.debug("Remember object {any} at {any}", .{ entity, place });
    self.remembered_objects.put(self.arena.allocator(), place, entity);
}

pub fn forgetObject(self: *Self, place: p.Point) !void {
    log.debug("Forget object at {any}", .{place});
    _ = try self.remembered_objects.remove(place);
}

/// Removes if exists the entity from inner index, or do nothing.
pub fn removeEntity(self: *Self, entity: g.Entity) !void {
    for (0..self.entities.items.len) |idx| {
        if (entity.eql(self.entities.items[idx])) {
            _ = self.entities.swapRemove(idx);
            return;
        }
    }
}

/// Adds an item to the list of entities on this level, and puts it at the specified place.
/// Three possible scenario can happened here:
///   - If no one other item on the place, then the item will be dropped as is:
///     the position and appropriate sprite will be added to the item;
///   - If some item (not a pile) is on the place, then a new pile
///     will be created and added at the place(a position, zorder and sprite will be added),
///     and both items will be added to that pile;
///   - If a pile is on the place, the item will be added to this pile;
///
/// Returns entity id for the pile if it was created;
pub fn addItemAtPlace(self: *Self, item: g.Entity, place: p.Point) !?g.Entity {
    switch (self.cellAt(place)) {
        .entities => |entities| {
            // if some item already exists on the place
            if (entities[1]) |entity| {
                // and that item is a pile
                if (self.registry.get(entity, c.Pile)) |pile| {
                    log.debug("Adding item {any} into the pile {any} at {any}", .{ item, entity, place });
                    // add a new item to the pile
                    try pile.items.add(item);
                    return entity;
                } else {
                    // or create a new pile and add the item to the pile
                    const pile_id = try self.registry.addNewEntity(
                        try g.entities.pile(self.registry.allocator(), place),
                    );
                    try self.entities.append(self.arena.allocator(), pile_id);
                    const pile = self.registry.getUnsafe(pile_id, c.Pile);
                    log.debug("Created a pile {any} at {any}", .{ pile_id, place });

                    // add the item to the pile
                    try pile.items.add(item);

                    // move the existed item to the pile
                    try pile.items.add(entity);
                    try self.registry.remove(entity, c.Position);
                    return pile_id;
                }
            }
        },
        else => {},
    }
    log.debug("Adding item {any} to the empty place {any}", .{ item, place });
    try self.registry.set(item, c.Position{ .place = place, .zorder = .item });
    try self.entities.append(self.arena.allocator(), item);
    return null;
}

pub inline fn checkVisibility(self: *const g.Level, place: p.Point) g.Render.Visibility {
    return self.visibility_strategy(self, place);
}

pub inline fn playerPosition(self: *const Self) *c.Position {
    return self.registry.getUnsafe(self.player, c.Position);
}

pub fn randomEmptyPlace(self: Self, rand: std.Random) ?p.Point {
    var attempt: u8 = 10;
    while (attempt > 0) : (attempt -= 1) {
        const place = self.dungeon.randomPlace(rand);
        switch (self.cellAt(place)) {
            .landscape => |landscape| if (landscape == .floor) return place,
            else => return null,
        }
    }
    return null;
}

pub fn obstacles(self: *const Self) u.DijkstraMap.Obstacles {
    return .{ .context = self, .isObstacleFn = isObstacleFn };
}

/// This function is used to build the DijkstraMap, that is used to navigate enemies,
/// and to check collision by the walking enemies.
fn isObstacleFn(ptr: *const anyopaque, place: p.Point) bool {
    const self: *const Self = @ptrCast(@alignCast(ptr));
    return isObstacle(self, place);
}

pub fn isObstacle(self: *const Self, place: p.Point) bool {
    switch (self.cellAt(place)) {
        .landscape => |cl| switch (cl) {
            .floor, .doorway => {},
            else => return true,
        },
        .entities => |entities| if (entities[2]) |entity|
            // an entity with health points is overcoming obstacle
            return self.registry.get(entity, c.Health) == null
        else
            // all other are not
            return false,
    }
    return false;
}

/// Returns the cell of the level:
///   - `.landscape` - any kind of the walls or the empty floor/doorway;
///   - `.entities` - an array of the entities on the place:
///       0 - opened doors, ladders, teleports;
///       1 - any dropped items;
///       2 - player, enemies, npc, closed doors;
pub fn cellAt(self: Self, place: p.Point) Cell {
    const landscape = switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => |cl| cl,
        else => |cl| return .{ .landscape = cl },
    };
    // OPTIMIZE IT
    var found_entity = false;
    // up to 3 entities with different z-orders may exists at same position
    var result = [3]?g.Entity{ null, null, null };
    var itr = self.registry.query(c.Position);
    while (itr.next()) |tuple| {
        const entity, const position = tuple;
        const order = @intFromEnum(position.zorder);
        if (position.place.eql(place)) {
            found_entity = true;
            // only one entity with the same order can be at the same place
            if (result[order]) |existed_item| {
                std.debug.panic(
                    "Both items {any} and {any} with order {s} at same place {any}",
                    .{ existed_item, entity, @tagName(position.zorder), place },
                );
            }
            result[order] = entity;
        }
    }
    return if (found_entity) .{ .entities = result } else .{ .landscape = landscape };
}

// OPTIMIZE IT
pub fn itemAt(self: Self, place: p.Point) ?g.Entity {
    switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => {},
        else => return null,
    }
    var itr = self.registry.query(c.Position);
    while (itr.next()) |tuple| {
        const entity, const position = tuple;
        if (place.eql(position.place) and position.zorder == .item) {
            return entity;
        }
    }
    return null;
}

// The level doesn't subscribe to event directly to avoid unsubscription.
// Instead, the PlayMode delegates events to the actual level.
pub fn onPlayerMoved(self: *Self, player_moved: g.events.EntityMoved) !void {
    std.debug.assert(player_moved.is_player);
    self.updatePlacement(player_moved.moved_from, player_moved.targetPlace());
    const player_place = self.playerPosition().place;
    try u.DijkstraMap.calculate(
        self.arena.allocator(),
        &self.dijkstra_map,
        DijkstraMapRegion.centralizedAround(player_place),
        self.obstacles(),
        player_place,
    );
}

fn updatePlacement(self: *Self, player_moved_from: p.Point, player_moved_to: p.Point) void {
    if (self.player_placement.contains(player_moved_to)) return;

    if (self.dungeon.doorwayAt(player_moved_from)) |doorway| {
        if (doorway.oppositePlacement(self.player_placement)) |opposite_placement| {
            if (opposite_placement.contains(player_moved_to)) {
                self.player_placement = opposite_placement;
                log.debug("Placement with player is {any}", .{opposite_placement});
                return;
            }
        }
    }
    if (self.dungeon.placementWith(player_moved_to)) |placement| {
        self.player_placement = placement;
        return;
    }
    log.err("It looks like the player at {any} is outside of any placement", .{player_moved_to});
}

fn addLadder(self: *g.Level, ladder: c.Ladder, place: p.Point) !void {
    try self.registry.setComponentsToEntity(ladder.id, g.entities.ladder(ladder, place));
    try self.entities.append(self.arena.allocator(), ladder.id);
}

fn addEnemy(self: *g.Level, rand: std.Random, enemy: c.Components) !void {
    const id = try self.registry.addNewEntity(enemy);
    try self.entities.append(self.arena.allocator(), id);
    const state: c.EnemyState = if (rand.uintLessThan(u8, 5) == 0) .sleeping else .walking;
    try self.registry.set(id, state);
}
