const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const Self = @This();

context: *anyopaque,

directionToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?p.Direction,
distanceToPlayerFn: *const fn (context: *anyopaque, from: p.Point) ?u8,
isObstacleFn: *const fn (context: *anyopaque, place: p.Point) bool,
tryToMoveFn: *const fn (context: *anyopaque, from: p.Point, target: g.Action.Payload.Move.Target) ?g.Action,
passesChanceFn: *const fn (context: *anyopaque, percent: u8) bool,

pub fn fromSession(session: *g.GameSession) Self {
    return .{
        .context = session,
        .distanceToPlayerFn = distanceToPlayer,
        .directionToPlayerFn = directionToPlayer,
        .isObstacleFn = isObstacle,
        .tryToMoveFn = tryToMove,
        .passesChanceFn = passesChance,
    };
}

fn directionToPlayer(ptr: *anyopaque, from: p.Point) ?p.Direction {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return if (session.level.dijkstra_map.get(from)) |vector|
        vector.direction
    else
        null;
}

fn distanceToPlayer(ptr: *anyopaque, from: p.Point) ?u8 {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return if (session.level.dijkstra_map.get(from)) |vector|
        vector.distance
    else
        null;
}

fn isObstacle(ptr: *anyopaque, place: p.Point) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));

    return session.level.isObstacle(place);
}

/// Returns the action required to move from `from_place` toward `target`,
/// or `null` if no action is possible.
fn tryToMove(
    ptr: *anyopaque,
    from_place: p.Point,
    target: g.Action.Payload.Move.Target,
) ?g.Action {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));

    const place = target.asPlace(from_place);
    if (from_place.eql(place)) return null;

    switch (session.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway) {
            return .action(.move, .{ .target = target });
        },

        .entities => |entities| {
            // Check obstacles
            if (entities[@intFromEnum(c.Position.ZOrder.obstacle)]) |entity| {
                if (session.registry.get(entity, c.Door)) |_| {
                    // TODO: not all enemies are able to open doors
                    return .action(.open, .{ .id = entity, .place = place });
                }

                if (g.meta.getEnemyType(&session.registry, entity)) |_| {
                    // TODO: should all enemies be aggressive to each other?
                    return .action(.wait, {});
                }

                return null;
            }
            // Check traps
            if (entities[@intFromEnum(c.Position.ZOrder.item)]) |entity| {
                if (session.registry.get(entity, c.Trap)) |_| {
                    return .action(.step_in_trap, .{ .trap_entity = entity, .moving_target = target });
                }
            }
            // it's possible to step on the ladder, opened door, teleport, dropped item and
            // other entities with ZOrder.floor
            return .action(.move, .{ .target = target });
        },
    }
    return null;
}

pub fn passesChance(ptr: *anyopaque, chance_percent: u8) bool {
    const session: *g.GameSession = @ptrCast(@alignCast(ptr));
    return session.prng.random().uintLessThan(u8, 100) < chance_percent;
}
