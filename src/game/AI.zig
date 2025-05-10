const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

const AI = @This();

session: *const g.GameSession,
rand: std.Random,

/// Calculates the next action for the entity.
/// Do not mutate anything, only creates an action.
pub fn action(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
) g.Action {
    const player_place = self.session.level.playerPosition().place;

    if (self.session.entities.get(entity, c.EnemyState)) |state| {
        const act = switch (state.*) {
            .sleeping => self.actionForSleepingEnemy(entity, entity_place, player_place),
            .walking => self.actionForWalkingEnemy(entity, entity_place, player_place),
            .aggressive => self.actionForAggressiveEnemy(entity, entity_place, player_place),
        };
        log.debug("The action for the entity {d} in state {s} is {any}", .{ entity.id, @tagName(state.*), act });
        return act;
    }
    return .wait;
}

inline fn actionForSleepingEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (entity_place.near(player_place)) return .{ .get_angry = entity };
    if (self.isPlayerIsInSight(entity_place)) {
        // TODO Probability of waking up should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) == 0) return .{ .get_angry = entity };
    }
    return .wait;
}

inline fn actionForWalkingEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (entity_place.near(player_place)) return .{ .get_angry = entity };

    if (self.isPlayerIsInSight(entity_place)) {
        // TODO Probability of become aggressive should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) > 3) return .{ .get_angry = entity };
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    self.rand.shuffle(p.Direction, &directions);
    for (directions) |direction| {
        const place = entity_place.movedTo(direction);
        if (self.session.level.obstacleAt(place)) |collision| {
            if (collision == .landscape) continue;
        }
        return .{ .move = .{ .target = .{ .direction = direction } } };
    }
    log.err("Entity {d} is stuck at {any}", .{ entity.id, entity_place });
    return .{ .go_sleep = entity };
}

inline fn actionForAggressiveEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (self.session.level.dijkstra_map.vectors.get(entity_place)) |vector| {
        if (entity_place.near(player_place)) {
            const weapon = self.session.entities.getUnsafe(entity, c.Weapon);
            return .{
                .hit = .{
                    .target = self.session.player,
                    .by_weapon = weapon.*,
                },
            };
        } else {
            return .{ .move = .{ .target = .{ .direction = vector[0] } } };
        }
    } else {
        return .{ .chill = entity };
    }
}

fn isPlayerIsInSight(self: AI, entity_place: p.Point) bool {
    if (!self.session.level.dijkstra_map.region.containsPointInside(entity_place)) return false;
    return self.session.level.checkVisibility(entity_place) == .visible;
}
