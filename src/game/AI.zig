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
    const player_place = self.session.level.playerPosition().point;

    if (self.session.level.components.getForEntity(entity, c.EnemyState)) |state| {
        const act = switch (state.*) {
            .sleep => self.actionForSleepingEnemy(entity, entity_place, player_place),
            .chill => self.actionForChillingEnemy(entity, entity_place, player_place),
            .hunt => self.actionForHuntingEnemy(entity, entity_place, player_place),
        };
        log.debug("The action for the entity {d} in state {s} is {any}", .{ entity, @tagName(state.*), act });
        return act;
    }
    return .wait;
}

inline fn actionForSleepingEnemy(
    _: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (entity_place.near(player_place)) return .{ .get_angry = entity };
    return .wait;
}

inline fn actionForChillingEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (entity_place.near(player_place)) return .{ .get_angry = entity };

    if (!self.session.level.dijkstra_map.region.containsPointInside(entity_place)) {
        return .wait;
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    self.rand.shuffle(p.Direction, &directions);
    for (directions) |direction| {
        const place = entity_place.movedTo(direction);
        if (self.session.level.collisionAt(place) == null) {
            return .{ .move = .{ .target = .{ .direction = direction } } };
        }
    }
    return .wait;
}

inline fn actionForHuntingEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (self.session.level.dijkstra_map.vectors.get(entity_place)) |vector| {
        if (entity_place.near(player_place)) {
            const health = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Health);
            const weapon = self.session.level.components.getForEntityUnsafe(entity, c.Weapon);
            return .{
                .hit = .{
                    .target = self.session.level.player,
                    .target_health = health,
                    .by_weapon = weapon,
                },
            };
        } else {
            return .{ .move = .{ .target = .{ .direction = vector[0] } } };
        }
    } else {
        return .{ .chill = entity };
    }
}
