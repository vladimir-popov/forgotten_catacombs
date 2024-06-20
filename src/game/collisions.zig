const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collisions);

const Obstacle = union(enum) {
    closed_door,
    wall,
    entity: game.Entity,
};

/// Should return true if it possible for entity to move to the new_point
pub fn handle(session: *game.GameSession, entity: game.Entity, new_point: p.Point) bool {
    if (collision(session, new_point)) |obstacle| {
        switch (obstacle) {
            .wall => return false,
            .closed_door => {
                session.dungeon.openDoor(new_point);
                return false;
            },
            .entity => |e| {
                if (session.components.getForEntity(entity, game.Health)) |agressor| {
                    if (session.components.getForEntity(e, game.Health)) |victim| {
                        return fight(session, entity, agressor, e, victim);
                    }
                }
                return false;
            },
        }
    } else {
        return true;
    }
}

fn collision(session: *game.GameSession, new_point: p.Point) ?Obstacle {
    if (session.dungeon.cellAt(new_point)) |cell| {
        switch (cell) {
            .nothing, .wall => return .wall,
            .door => |door| if (door == .opened) return null else return .closed_door,
            .entity => |e| return .{ .entity = e },
            .floor => if (entityAt(session, new_point)) |e| return .{ .entity = e } else return null,
        }
    }
    return .wall;
}

fn entityAt(session: *game.GameSession, place: p.Point) ?game.Entity {
    for (session.components.arrayOf(game.Position).components.items, 0..) |pos, idx| {
        if (pos.point.eql(place)) {
            return session.components.arrayOf(game.Position).index_entity.get(@intCast(idx));
        }
    }
    return null;
}

fn fight(
    session: *game.GameSession,
    _: game.Entity,
    _: *game.Health,
    _: game.Entity,
    vict_health: *game.Health,
) bool {
    if (session.runtime.rand.boolean()) {
        const damage = 1;
        vict_health.damage = 1;
        return vict_health.hp <= damage;
    }
    return false;
}
