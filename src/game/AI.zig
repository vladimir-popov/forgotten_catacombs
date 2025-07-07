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
    enemy_state: c.EnemyState,
) g.Action {
    const player_place = self.session.level.playerPosition().place;

    const act = switch (enemy_state) {
        .sleeping => self.actionForSleepingEnemy(entity, entity_place, player_place),
        .walking => self.actionForWalkingEnemy(entity, entity_place, player_place),
        .aggressive => self.actionForAggressiveEnemy(entity, entity_place, player_place),
    };
    log.debug("The action for the entity {d} in state {s} is {any}", .{ entity.id, @tagName(enemy_state), act });
    return act;
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
    const level = &self.session.level;
    for (directions) |direction| {
        const place = entity_place.movedTo(direction);
        if (level.isObstacle(place)) continue;
        return .{ .move = .{ .target = .{ .direction = direction } } };
    }
    log.err("Entity {d} is stuck at {any}. Sleep.", .{ entity.id, entity_place });
    return .{ .go_sleep = entity };
}

inline fn actionForAggressiveEnemy(
    self: AI,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.Action {
    if (entity_place.near(player_place)) {
        if (self.session.getWeapon(entity)) |weapon|
            return .{
                .hit = .{
                    .target = self.session.player,
                    .by_weapon = weapon.*,
                },
            };
    }
    const level = &self.session.level;
    if (level.dijkstra_map.get(entity_place)) |vector| {
        log.debug(
            "Entity {any} moves to the player from {any} in direction {s}",
            .{ entity, entity_place, @tagName(vector.direction) },
        );
        return .{ .move = .{ .target = .{ .direction = vector.direction } } };
    } else {
        log.info("Player is out of reach for {any} (from {any}). Chill.", .{ entity, entity_place });
        return .{ .chill = entity };
    }
}

fn isPlayerIsInSight(self: AI, entity_place: p.Point) bool {
    return if (self.session.level.dijkstra_map.get(entity_place)) |vector|
        vector.distance > 0
    else
        false;
}
