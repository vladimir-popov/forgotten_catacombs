const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const DecisionContext = @import("DecisionContext.zig");
const Environment = @import("Environment.zig");

const log = std.log.scoped(.ai);

const Self = @This();

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
        .rand = self.session().prng.random(),
        .enemy = npc,
        .enemy_place = self.session().registry.getUnsafe(npc, c.Position).place,
        .enemy_stats = self.session().registry.getUnsafe(npc, c.Stats),
        .player = self.session().player,
        .player_place = self.session().level.playerPosition().place,
        .player_stats = self.session().registry.getUnsafe(self.session().player, c.Stats),
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
        const chance = noticePlayerChance(
            .sleeping,
            context.enemy_stats.get(.perception),
            distance,
            context.player_stats.get(.dexterity),
        );
        if (context.passesChance(chance)) return .action(.get_angry, context.enemy);
    }
    return .action(.wait, {});
}

/// Returns an action or null if not enough move points.
fn actionForWalkingEnemy(context: DecisionContext) ?g.Action {
    if (context.speed.moving_speed > context.max_move_points)
        return null;

    if (context.distanceToPlayer()) |distance| {
        const chance = noticePlayerChance(
            .walking,
            context.enemy_stats.get(.perception),
            distance,
            context.player_stats.get(.dexterity),
        );
        if (context.passesChance(chance)) return .action(.get_angry, context.enemy);
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

fn noticePlayerChance(enemy_state: c.EnemyState, enemy_perception: i4, distance_to_player: u8, player_dexterity: i4) u8 {
    const base: i16 = 110 - 20 * @as(i16, distance_to_player);
    const perception: i16 = 10 * @as(i16, enemy_perception);
    const dexterity: i16 = 10 * @as(i16, player_dexterity);

    var chance = base + perception - dexterity;
    if (enemy_state == .sleeping)
        chance = @divTrunc(chance, 2);

    return @intCast(std.math.clamp(chance, 0, 100));
}

const TestEnvironment = @import("TestEnvironment.zig");

pub fn decisionContextForTest(rand: std.Random, environment: Environment) DecisionContext {
    return .{
        .rand = rand,
        .player = .{ .id = 1 },
        .player_place = .point(3, 3),
        .player_stats = &c.Stats.zeros,
        .enemy = .{ .id = 2 },
        .enemy_place = .point(3, 3),
        .enemy_stats = &c.Stats.zeros,
        .speed = &c.Speed.default,
        .max_move_points = g.MOVE_POINTS_IN_TURN,
        .environment = environment,
    };
}

test "sleeping enemy next to the player can become aggressive" {
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{ .distance_to_player = 1, .minimal_percent_to_chance = 0 };
    const context = decisionContextForTest(prng.random(), env.environment());

    const action = actionForSleepingEnemy(context).?;

    try std.testing.expectEqual(g.actions.Action.Tag.get_angry, action.tag);
    try std.testing.expect(action.payload.get_angry.eql(context.enemy));
}
