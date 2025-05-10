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

pub inline fn removeEntity(self: *Level, entity: g.Entity) !void {
    try self.session.entities.removeEntity(entity);
    for (0..self.entities.items.len) |idx| {
        if (entity.eql(self.entities.items[idx])) {
            _ = self.entities.swapRemove(idx);
            return;
        }
    }
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
        .entities => |entities| if (entities[2] != null) return true,
    }
    return false;
}

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
        if (place.eql(position.place)) {
            found_entity = true;
            // only one entity with the same order can be at the same place
            std.debug.assert(result[zorder.order] == null);
            result[zorder.order] = entity;
        }
    }
    return if (found_entity) .{ .entities = result } else .{ .landscape = landscape };
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
