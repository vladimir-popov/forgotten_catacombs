const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

const Self = @This();

session: *const g.GameSession,
rand: std.Random,

/// Chooses the next action for the entity, or returns
/// `null` if the initiative is not enough for any action.
pub fn chooseAction(
    self: *const Self,
    npc: g.Entity,
    speed: *const c.Speed,
    initiative: *const c.Initiative,
) ?g.Action {
    const npc_place = self.session.registry.getUnsafe(npc, c.Position).place;
    const npc_state = self.session.registry.getUnsafe(npc, c.EnemyState);
    const player_place = self.session.level.playerPosition().place;

    return switch (npc_state.*) {
        .sleeping => self.actionForSleepingEnemy(npc, npc_place, player_place, speed, initiative.move_points),
        .walking => self.actionForWalkingEnemy(npc, npc_place, player_place, speed, initiative.move_points),
        .aggressive => self.actionForAggressiveEnemy(npc, npc_place, player_place, speed, initiative.move_points),
    };
}

fn actionForSleepingEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
    speed: *const c.Speed,
    max_move_points: u8,
) ?g.Action {
    if (speed.moving_speed > max_move_points)
        return null;

    if (entity_place.near8(player_place))
        return .action(.get_angry, entity);

    if (self.isPlayerIsInSight(entity_place)) {
        // TODO Probability of waking up should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) == 0) return .action(.get_angry, entity);
    }
    return .action(.wait, {});
}

/// Returns an action or null if not enough move points.
fn actionForWalkingEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
    speed: *const c.Speed,
    max_move_points: u8,
) ?g.Action {
    if (entity_place.near8(player_place) and speed.moving_speed <= max_move_points)
        return .action(.get_angry, entity);

    if (self.isPlayerIsInSight(entity_place) and speed.moving_speed <= max_move_points) {
        // TODO Probability of become aggressive should depends on player's skills
        if (self.rand.uintLessThan(u8, 10) > 3) return .action(.get_angry, entity);
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    self.rand.shuffle(p.Direction, &directions);
    const level = &self.session.level;
    for (directions) |direction| {
        const place = entity_place.movedTo(direction);
        if (level.isObstacle(place)) continue;
        const act: g.Action = self.tryToMove(place, .{ .direction = direction }) orelse .action(.wait, {});
        if (act.movePoints(speed) <= max_move_points) {
            return act;
        }
    }
    log.err("Entity {d} is stuck at {any}. Sleep.", .{ entity.id, entity_place });
    if (speed.moving_speed <= max_move_points)
        return .action(.go_sleep, entity);

    return null;
}

/// Returns an action or null if not enough move points.
fn actionForAggressiveEnemy(
    self: *const Self,
    entity: g.Entity,
    entity_place: p.Point,
    player_place: p.Point,
    speed: *const c.Speed,
    max_move_points: u8,
) ?g.Action {
    if (entity_place.near4(player_place) and speed.atack_speed <= max_move_points) {
        return .action(.hit, self.session.player);
    }
    const level = &self.session.level;
    if (level.dijkstra_map.get(entity_place)) |vector| {
        log.debug(
            "Entity {any} moves to the player from {any} in direction {s}",
            .{ entity, entity_place, @tagName(vector.direction) },
        );
        const act: g.Action = self.tryToMove(entity_place, .{ .direction = vector.direction }) orelse .action(.wait, {});
        if (act.movePoints(speed) <= max_move_points) {
            return act;
        }
    } else if (speed.moving_speed <= max_move_points) {
        log.info("Player is out of reach for {any} (from {any}). Chill.", .{ entity, entity_place });
        return .action(.chill, entity);
    }
    return null;
}

fn isPlayerIsInSight(self: *const Self, entity_place: p.Point) bool {
    return if (self.session.level.dijkstra_map.get(entity_place)) |vector|
        vector.distance > 0
    else
        false;
}

/// Returns the action required to move from `from_place` toward `target`,
/// or `null` if no action is possible.
fn tryToMove(
    self: *const Self,
    from_place: p.Point,
    target: g.Action.Payload.Move.Target,
) ?g.Action {
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
                    return .action(.wait, {});
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
