//! Selects NPC actions according to their state and available move points.
//! Embedded in `GameSession`, it builds a `DecisionContext` from session data
//! so behavior rules can also be exercised independently in tests.
//! Returns an action for the caller to execute, or `null` if none is selected.
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
        .weapon_range = g.meta.getWeapon(&self.session().registry, npc)[1].max_distance,
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

    if (context.movesToPlayer()) |moves| {
        const chance = noticePlayerChance(
            .sleeping,
            context.enemy_stats.get(.perception),
            moves,
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

    if (context.movesToPlayer()) |moves| {
        const chance = noticePlayerChance(
            .walking,
            context.enemy_stats.get(.perception),
            moves,
            context.player_stats.get(.dexterity),
        );
        if (context.passesChance(chance)) return .action(.get_angry, context.enemy);
    }

    var directions = [4]p.Direction{ .left, .up, .right, .down };
    context.rand.shuffle(p.Direction, &directions);
    for (directions) |direction| {
        if (context.checkCollision(.{ .direction = direction }) == .obstacle)
            continue;

        const act: g.Action = tryToMove(context, .{ .direction = direction }) orelse .action(.wait, {});
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
    const distance = context.player_place.distanceTo(context.enemy_place);
    // TODO: test a case with diagonals
    if (context.weapon_range <= distance and context.speed.atack_speed <= context.max_move_points) {
        return .action(.hit, context.player);
    }
    if (context.directionToPlayer()) |direction| {
        log.debug(
            "Entity {any} moves to the player from {any} in direction {t}",
            .{ context.enemy.id, context.enemy_place, direction },
        );
        const act: g.Action = tryToMove(context, .{ .direction = direction }) orelse .action(.wait, {});
        if (act.movePoints(context.speed) <= context.max_move_points) {
            return act;
        }
    } else if (context.speed.moving_speed <= context.max_move_points) {
        log.info("Player is out of reach for {any} (from {any}). Chill.", .{ context.enemy.id, context.enemy_place });
        return .action(.chill, context.enemy);
    }
    return null;
}

/// Calculates the chance that an enemy notices the player based on the
/// number of Dijkstra-map steps between them, not their direct distance.
/// This models hearing: more steps reduce the chance, while enemy perception
/// and player dexterity adjust it. Sleeping enemies have half the chance.
fn noticePlayerChance(enemy_state: c.EnemyState, enemy_perception: i4, moves_to_player: u8, player_dexterity: i4) u8 {
    const base: i16 = 110 - 20 * @as(i16, moves_to_player);
    const perception: i16 = 10 * @as(i16, enemy_perception);
    const dexterity: i16 = 10 * @as(i16, player_dexterity);

    var chance = base + perception - dexterity;
    if (enemy_state == .sleeping)
        chance = @divTrunc(chance, 2);

    return @intCast(std.math.clamp(chance, 0, 100));
}

/// Returns the action required to move from `from_place` toward `target`,
/// or `null` if no action is possible.
fn tryToMove(
    context: DecisionContext,
    target: g.Action.Payload.Move.Target,
) ?g.Action {
    return switch (context.checkCollision(target)) {
        .obstacle => null,
        .nothing => .action(.move, .{ .target = target }),
        // TODO: not all enemies are able to open doors
        .door => |door| .action(.open, .{ .id = door[0], .place = target.asPlace(context.enemy_place) }),
        // TODO: should all enemies be aggressive to each other?
        .enemy => .action(.wait, {}),
        .trap => |trap| .action(.step_in_trap, .{ .trap_entity = trap[0], .moving_target = target }),
        .player => .action(.hit, context.player),
    };
}

const TestEnvironment = @import("TestEnvironment.zig");

pub fn decisionContextForTest(rand: std.Random, environment: Environment) DecisionContext {
    return .{
        .rand = rand,
        .player = .{ .id = 1 },
        .player_place = .point(3, 3),
        .player_stats = &c.Stats.zeros,
        .weapon_range = 1,
        .enemy = .{ .id = 2 },
        .enemy_place = .point(3, 3),
        .enemy_stats = &c.Stats.zeros,
        .speed = &c.Speed.default,
        .max_move_points = g.MOVE_POINTS_IN_TURN,
        .environment = environment,
    };
}

test "aggressive enemy uses attack cost rather than movement cost to attack" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    const direction_to_player = .right;
    var env = TestEnvironment{
        .direction_to_player = direction_to_player,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    context.player_place = context.enemy_place.movedTo(direction_to_player);
    try env.collisions.put(std.testing.allocator, context.player_place, .player);
    const speed = c.Speed{ .moving_speed = 10, .atack_speed = 8 };
    context.speed = &speed;
    // Exactly enough for an attack, but not enough for a step.
    context.max_move_points = speed.atack_speed;

    // when:
    const action = actionForAggressiveEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.hit, action.tag);
    try std.testing.expectEqual(context.player, action.payload.hit);
}

test "aggressive enemy cannot attack the player diagonally and moves closer" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = .right,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is one cell down and one cell right of the NPC.
    // Both actions are affordable, but diagonal melee attacks are not allowed.
    context.player_place = .point(4, 4);

    // when:
    const action = actionForAggressiveEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.move, action.tag);
    try std.testing.expectEqual(p.Direction.right, action.payload.move.target.direction);
}

test "aggressive enemy pursues the player with enough points to move but not attack" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = .right,
    };
    const speed = c.Speed{ .moving_speed = 8, .atack_speed = 10 };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is three cells to the right of the NPC, outside melee reach.
    context.player_place = .point(3, 6);
    context.speed = &speed;
    // Exactly enough for movement; attack cost must not prevent pursuit.
    context.max_move_points = speed.moving_speed;

    // when:
    const action = actionForAggressiveEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.move, action.tag);
    try std.testing.expectEqual(p.Direction.right, action.payload.move.target.direction);
}

test "aggressive enemy postpones pursuit without enough move points" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = .right,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is three cells to the right of the NPC, outside melee reach.
    context.player_place = .point(3, 6);
    // One point short checks the boundary below the cost of pursuit.
    context.max_move_points = context.speed.moving_speed - 1;

    // when:
    const action = actionForAggressiveEnemy(context);

    // then:
    try std.testing.expect(action == null);
}

test "aggressive enemy waits when it cannot take a step toward the player (it can be another enemy on the way)" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = .right,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is three cells to the right of the NPC, outside melee reach.
    context.player_place = .point(3, 6);
    // But an obstacle is on the nearest cell
    try env.obstacles.put(std.testing.allocator, context.enemy_place.movedTo(env.direction_to_player), .obstacle);

    // when:
    const action = actionForAggressiveEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.wait, action.tag);
}

test "aggressive enemy calms down when the player is out of reach" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = null,
        .moves_to_player = null,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is three cells to the right of the NPC, with no route to them.
    context.player_place = .point(3, 6);

    // when:
    const action = actionForAggressiveEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.chill, action.tag);
    try std.testing.expectEqual(context.enemy, action.payload.chill);
}

test "aggressive enemy postpones calming down without enough move points" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .direction_to_player = null,
        .moves_to_player = null,
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // The player is three cells to the right of the NPC, with no route to them.
    context.player_place = .point(3, 6);
    // Calming down costs movement points too; one point short must defer it.
    context.max_move_points = context.speed.moving_speed - 1;

    // when:
    const action = actionForAggressiveEnemy(context);

    // then:
    try std.testing.expect(action == null);
}

test "walking enemy does not act without enough move points" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = 1,
        // 0 guarantees a positive detection chance succeeds, but the NPC
        // lacks move points and should not select any action yet.
        .minimal_percent_to_chance = 0,
        // Movement is available: insufficient move points should prevent
        // acting even when the surroundings allow a step.
        .moving_action = .action(.move, .{ .target = .{ .direction = .right } }),
    };
    var context = decisionContextForTest(prng.random(), env.environment());
    // One point short checks the boundary just below the action's cost.
    context.max_move_points = context.speed.moving_speed - 1;

    // when:
    const action = actionForWalkingEnemy(context);

    // then:
    try std.testing.expect(action == null);
}

test "walking enemy becomes aggressive instead of moving when it notices the player" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = 1,
        // 0 guarantees success for the positive detection chance here.
        // Noticing the player should take priority over continuing the walk.
        .minimal_percent_to_chance = 0,
        // Offer a movement alternative to verify that noticing the player
        // takes priority even when the NPC could continue walking.
        .moving_action = .action(.move, .{ .target = .{ .direction = .right } }),
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForWalkingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.get_angry, action.tag);
    try std.testing.expectEqual(context.enemy, action.payload.get_angry);
}

test "walking enemy continues walking when the player is not noticed" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var obstacles = [_]p.Point{ .point(3, 2), .point(2, 3), .point(4, 3) };
    var env = TestEnvironment{
        .moves_to_player = 1,
        // 100 guarantees detection fails despite the player being nearby.
        // The NPC should continue walking through the available passage.
        .minimal_percent_to_chance = 100,
        .obstacles = &obstacles,
        .moving_action = .action(.move, .{ .target = .{ .direction = .right } }),
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForWalkingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.move, action.tag);
    try std.testing.expectEqual(p.Direction.right, action.payload.move.target.direction);
}

test "walking enemy continues walking when the player is out of reach" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var obstacles = [_]p.Point{ .point(3, 2), .point(2, 3), .point(4, 3) };
    var env = TestEnvironment{
        .moves_to_player = null,
        // 0 makes any positive detection chance succeed, but the player is
        // out of reach. The NPC should continue walking rather than get angry.
        .minimal_percent_to_chance = 0,
        .obstacles = &obstacles,
        .moving_action = .action(.move, .{ .target = .{ .direction = .right } }),
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForWalkingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.move, action.tag);
    try std.testing.expectEqual(p.Direction.right, action.payload.move.target.direction);
}

test "walking enemy waits when it cannot take a step" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = null,
        .moving_action = null,
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForWalkingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.Action.Tag.wait, action.tag);
}

test "sleeping enemy does not act without enough move points" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{};
    var context = decisionContextForTest(prng.random(), env.environment());
    context.max_move_points = context.speed.moving_speed - 1;

    // when:
    const action = actionForSleepingEnemy(context);

    // then:
    try std.testing.expect(action == null);
}

test "sleeping enemy next to the player can become aggressive" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = 1,
        // 0 guarantees success for the positive detection chance here.
        // The NPC notices the nearby player, so it should choose get_angry.
        .minimal_percent_to_chance = 0,
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForSleepingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.actions.Action.Tag.get_angry, action.tag);
    try std.testing.expectEqual(context.enemy, action.payload.get_angry);
}

test "sleeping enemy stays asleep when the player is not noticed" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = 1,
        // 100 guarantees detection fails even though the player is nearby.
        // The NPC should stay asleep and choose wait.
        .minimal_percent_to_chance = 100,
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForSleepingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.actions.Action.Tag.wait, action.tag);
}

test "sleeping enemy stays asleep when the player is out of reach" {
    // given:
    var prng = std.Random.DefaultPrng.init(std.testing.random_seed);
    var env = TestEnvironment{
        .moves_to_player = null,
        // 0 makes any positive detection chance succeed, but the player is
        // out of reach. The NPC should still stay asleep and choose wait.
        .minimal_percent_to_chance = 0,
    };
    const context = decisionContextForTest(prng.random(), env.environment());

    // when:
    const action = actionForSleepingEnemy(context).?;

    // then:
    try std.testing.expectEqual(g.actions.Action.Tag.wait, action.tag);
}
