/// This is value object which represents the current level of the game session.
/// The level consist of the dungeon and entities.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const ecs = g.ecs;
const p = g.primitives;

const log = std.log.scoped(.level);

const Level = @This();

pub const Cell = union(enum) {
    landscape: d.Dungeon.Cell,
    entities: [3]?g.Entity,
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// The depth of the current level. The session_seed + depth is unique seed for the level.
depth: u8,
/// The list of the entities belong to this level.
// The ArrayList is used instead of HashMap to provide better performance on iterating over items,
// coz it happens more often than lookup the items inside this list.
entities: std.ArrayListUnmanaged(g.Entity),
visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
dungeon: d.Dungeon = undefined,
player_placement: d.Placement = undefined,
map: g.LevelMap = undefined,
/// Dijkstra Map to the player
dijkstra_map: g.DijkstraMap = undefined,

pub fn init(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    depth: u8,
    visibility_strategy: *const fn (level: *const g.Level, place: p.Point) g.Render.Visibility,
) !Level {
    var arena = std.heap.ArenaAllocator.init(alloc);
    var entities: std.ArrayListUnmanaged(g.Entity) = .empty;
    try entities.append(arena.allocator(), session.player);
    return .{
        .arena = arena,
        .session = session,
        .depth = depth,
        .entities = entities,
        .visibility_strategy = visibility_strategy,
    };
}

pub fn deinit(self: *Level) void {
    self.arena.deinit();
}

pub inline fn addEntity(self: *Level, entity: g.Entity) !void {
    try self.entities.append(self.arena.allocator(), entity);
}

pub fn removeEntity(self: *Level, entity: g.Entity) !void {
    try self.session.entities.removeEntity(entity);
    for (0..self.entities.items.len) |idx| {
        if (entity.eql(self.entities.items[idx])) {
            _ = self.entities.swapRemove(idx);
            return;
        }
    }
}

/// Adds an item to the list of entities on this level, and put it at the place.
/// Three possible scenario can happened here:
///   - If no one other item on the place, then the item will be dropped as is:
///     the position and appropriate sprite will be added to the item;
///   - If some item (not a pile) is on the place, then a new pile
///     will be created and added at the place(a position, zorder and sprite will be added),
///     and both items will be added to that pile;
///   - If a pile is on the place, the item will be added to this pile;
///
/// Returns entity id for the pile if it was created;
pub fn addEntityAtPlace(self: *Level, item: g.Entity, place: p.Point) !?g.Entity {
    switch (self.cellAt(place)) {
        .entities => |entities| {
            // if some item already exists on the place
            if (entities[1]) |entity| {
                // and that item is a pile
                if (self.session.entities.get(entity, c.Pile)) |pile| {
                    log.debug("Adding item {any} into the pile {any} at {any}", .{ item, entity, place });
                    // add a new item to the pile
                    try pile.add(item);
                    return entity;
                } else {
                    // or create a new pile and add the item to the pile
                    const pile_id = try self.session.entities.addNewEntityAllocate(g.entities.pile);
                    try self.session.entities.set(pile_id, c.Position{ .place = place });
                    try self.addEntity(pile_id);
                    const pile = self.session.entities.getUnsafe(pile_id, c.Pile);
                    log.debug("Created a pile {any} at {any}", .{ pile_id, place });

                    // add the item to the pile
                    try pile.add(item);

                    // move the existed item to the pile
                    try pile.add(entity);
                    try self.session.entities.remove(entity, c.Position);
                    return pile_id;
                }
            }
        },
        else => {},
    }
    log.debug("Adding item {any} to the empty place {any}", .{ item, place });
    try self.session.entities.set(item, c.Position{ .place = place });
    try self.addEntity(item);
    return null;
}

pub inline fn checkVisibility(self: *const g.Level, place: p.Point) g.Render.Visibility {
    return self.visibility_strategy(self, place);
}

pub inline fn playerPosition(self: *const Level) *c.Position {
    return self.session.entities.getUnsafe(self.session.player, c.Position);
}

pub inline fn componentsIterator(self: Level) g.ComponentsIterator {
    return self.session.entities.iterator(self.entities.items);
}

pub fn randomEmptyPlace(self: Level, rand: std.Random) ?p.Point {
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

pub fn obstacles(self: *const Level) g.DijkstraMap.Obstacles {
    return .{ .context = self, .isObstacleFn = isObstacleFn };
}

/// This function is used to build the DijkstraMap, that is used to navigate enemies,
/// and to check collision by the walking enemies.
fn isObstacleFn(ptr: *const anyopaque, place: p.Point) bool {
    const self: *const Level = @ptrCast(@alignCast(ptr));
    return isObstacle(self, place);
}

pub fn isObstacle(self: *const Level, place: p.Point) bool {
    switch (self.cellAt(place)) {
        .landscape => |cl| switch (cl) {
            .floor, .doorway => {},
            else => return true,
        },
        .entities => |entities| if (entities[2]) |entity|
            // an entity with health points is overcoming obstacle
            return self.session.entities.get(entity, c.Health) == null
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
pub fn cellAt(self: Level, place: p.Point) Cell {
    const landscape = switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => |cl| cl,
        else => |cl| return .{ .landscape = cl },
    };
    // OPTIMIZE IT
    var found_entity = false;
    var result = [3]?g.Entity{ null, null, null };
    var itr = self.componentsIterator().of2(c.Position, c.ZOrder);
    while (itr.next()) |tuple| {
        const entity, const position, const zorder = tuple;
        const order = @intFromEnum(zorder.order);
        if (place.eql(position.place)) {
            found_entity = true;
            // only one entity with the same order can be at the same place
            if (result[order]) |existed_item| {
                std.debug.panic("Both items {any} and {any} at same place {any}", .{ existed_item, entity, place });
            }
            result[order] = entity;
        }
    }
    return if (found_entity) .{ .entities = result } else .{ .landscape = landscape };
}

// OPTIMIZE IT
pub fn itemAt(self: Level, place: p.Point) ?g.Entity {
    switch (self.dungeon.cellAt(place)) {
        .floor, .doorway => {},
        else => return null,
    }
    var itr = self.componentsIterator().of2(c.Position, c.ZOrder);
    while (itr.next()) |tuple| {
        const entity, const position, const zorder = tuple;
        if (place.eql(position.place) and zorder.order == .item) {
            return entity;
        }
    }
    return null;
}

// The level doesn't subscribe to event directly to avoid unsubscription.
// Instead, the PlayMode delegates events to the actual level.
pub fn onPlayerMoved(self: *Level, player_moved: g.events.EntityMoved) !void {
    std.debug.assert(player_moved.is_player);
    self.updatePlacement(player_moved.moved_from, player_moved.targetPlace());
    const player_place = self.playerPosition().place;
    self.dijkstra_map.region.centralizeAround(player_place);
    try self.dijkstra_map.calculate(player_place);
}

fn updatePlacement(self: *Level, player_moved_from: p.Point, player_moved_to: p.Point) void {
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
