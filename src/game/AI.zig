const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

const Self = @This();

session: *const g.GameSession,
rand: std.Random,

/// Calculates the next action for the entity.
/// Do not mutate anything, only creates an action.
pub fn action(
    self: *const Self,
    npc: g.Entity,
) g.actions.Action {
    const npc_place = self.session.registry.getUnsafe(npc, c.Position).place;
    const npc_state = self.session.registry.getUnsafe(npc, c.EnemyState);
    const player_place = self.session.level.playerPosition().place;

    const act = switch (npc_state.*) {
        .sleeping => self.actionForSleepingEnemy(npc, npc_place, player_place),
        .walking => self.actionForWalkingEnemy(npc, npc_place, player_place),
        .aggressive => self.actionForAggressiveEnemy(npc, npc_place, player_place),
    };
    log.debug("The action for the entity {d} in state {s} is {any}", .{ npc.id, @tagName(npc_state.*), act });
    return act;
}

fn actionForSleepingEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.actions.Action {
    if (entity_place.near8(player_place)) return .action(.get_angry, entity);
    if (self.isPlayerIsInSight(entity_place)) {
        // TODO Probability of waking up should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) == 0) return .action(.get_angry, entity);
    }
    return .action(.wait, {});
}

fn actionForWalkingEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.actions.Action {
    if (entity_place.near8(player_place)) return .action(.get_angry, entity);

    if (self.isPlayerIsInSight(entity_place)) {
        // TODO Probability of become aggressive should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) > 3) return .action(.get_angry, entity);
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    self.rand.shuffle(p.Direction, &directions);
    const level = &self.session.level;
    for (directions) |direction| {
        const place = entity_place.movedTo(direction);
        if (level.isObstacle(place)) continue;
        return self.tryToMove(place, .{ .direction = direction }) orelse .action(.wait, {});
    }
    log.err("Entity {d} is stuck at {any}. Sleep.", .{ entity.id, entity_place });
    return .action(.go_sleep, entity);
}

fn actionForAggressiveEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
) g.actions.Action {
    if (entity_place.near4(player_place)) {
        return .action(.hit, self.session.player);
    }
    const level = &self.session.level;
    if (level.dijkstra_map.get(entity_place)) |vector| {
        log.debug(
            "Entity {any} moves to the player from {any} in direction {s}",
            .{ entity, entity_place, @tagName(vector.direction) },
        );
        return self.tryToMove(entity_place, .{ .direction = vector.direction }) orelse .action(.wait, {});
    } else {
        log.info("Player is out of reach for {any} (from {any}). Chill.", .{ entity, entity_place });
        return .action(.chill, entity);
    }
}

fn isPlayerIsInSight(self: *const Self, entity_place: p.Point) bool {
    return if (self.session.level.dijkstra_map.get(entity_place)) |vector|
        vector.distance > 0
    else
        false;
}

fn tryToMove(self: *const Self, from_place: p.Point, target: g.Action.Payload.Move.Target) ?g.Action {
    const place = target.asPlace(from_place);
    if (from_place.eql(place)) return null;

    switch (self.session.level.cellAt(place)) {
        .landscape => |cl| if (cl == .floor or cl == .doorway) {
            return .action(.move, .{ .target = target });
        },

        .entities => |entities| {
            // Check obstacles
            if (entities[@intFromEnum(c.Position.ZOrder.obstacle)]) |entity| {
                if (self.session.registry.get(entity, c.Door)) |_| {
                    // TODO: not all enemies are able to open doors
                    return .action(.open, .{ .id = entity, .place = place });
                }

                if (g.meta.getEnemyType(&self.session.registry, entity)) |_| {
                    // TODO: should all enemies be aggressive to each other?
                    return .action(.hit, entity);
                }

                return null;
            }
            // Check traps
            if (entities[@intFromEnum(c.Position.ZOrder.item)]) |entity| {
                if (self.session.registry.get(entity, c.Trap)) |_| {
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
