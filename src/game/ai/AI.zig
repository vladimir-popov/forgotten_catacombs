const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const DecisionContext = @import("DecisionContext.zig");
const Environment = @import("Environment.zig");

const log = std.log.scoped(.ai);

const Self = @This();

rand: std.Random,

inline fn session(self: *Self) *g.GameSession {
    return @alignCast(@fieldParentPtr("ai", self));
}

/// Chooses the next action for the entity, or returns
/// `null` if the initiative is not enough for any action.
pub fn chooseAction(
    self: *Self,
    npc: g.Entity,
    speed: *const c.Speed,
    initiative: *const c.Initiative,
) ?g.Action {
    const context = DecisionContext{
        .rand = self.rand,
        .enemy = npc,
        .enemy_place = self.session().registry.getUnsafe(npc, c.Position).place,
        .player = self.session().player,
        .player_place = self.session().level.playerPosition().place,
        .speed = speed,
        .max_move_points = initiative.move_points,
        .environment = Environment.fromSession(self.session()),
    };
    const npc_state = self.session().registry.getUnsafe(npc, c.EnemyState);

    return switch (npc_state.*) {
        .sleeping => actionForSleepingEnemy(context),
        .walking => actionForWalkingEnemy(context),
        .aggressive => actionForAggressiveEnemy(context),
    };
}

fn actionForSleepingEnemy(context: DecisionContext) ?g.Action {
    if (context.speed.moving_speed > context.max_move_points)
        return null;

    if (context.distanceToPlayer()) |distance| {
        // TODO Probability of waking up should depends on player's skills + penalty for sleeping
        if (context.rand.uintLessThan(u8, 10) > distance) return .action(.get_angry, context.enemy);
    }
    return .action(.wait, {});
}

/// Returns an action or null if not enough move points.
fn actionForWalkingEnemy(context: DecisionContext) ?g.Action {
    if (context.speed.moving_speed > context.max_move_points)
        return null;

    if (context.distanceToPlayer()) |distance| {
        // TODO Probability of waking up should depends on player's skills
        if (context.rand.uintLessThan(u8, 10) > distance) return .action(.get_angry, context.enemy);
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    context.rand.shuffle(p.Direction, &directions);
    for (directions) |direction| {
        const place = context.enemy_place.movedTo(direction);
        if (context.isObstacle(place)) continue;
        const act: g.Action = context.tryToMove(.{ .direction = direction }) orelse .action(.wait, {});
        if (act.movePoints(context.speed) <= context.max_move_points) {
            return act;
        }
    }
    log.err("Entity {d} is stuck at {any}. Sleep.", .{ context.enemy.id, context.enemy_place });
    if (context.speed.moving_speed > context.max_move_points)
        return .action(.go_sleep, context.enemy);

    return null;
}

/// Returns an action or null if not enough move points.
fn actionForAggressiveEnemy(context: DecisionContext) ?g.Action {
    if (context.enemy_place.near4(context.player_place) and context.speed.atack_speed <= context.max_move_points) {
        return .action(.hit, context.player);
    }
    if (context.directionToPlayer()) |direction| {
        log.debug(
            "Entity {any} moves to the player from {any} in direction {t}",
            .{ context.enemy.id, context.enemy_place, direction },
        );
        const act: g.Action = context.tryToMove(.{ .direction = direction }) orelse .action(.wait, {});
        if (act.movePoints(context.speed) <= context.max_move_points) {
            return act;
        }
    } else if (context.speed.moving_speed <= context.max_move_points) {
        log.info("Player is out of reach for {any} (from {any}). Chill.", .{ context.enemy.id, context.enemy_place });
        return .action(.chill, context.enemy);
    }
    return null;
}
