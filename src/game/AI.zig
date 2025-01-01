const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

/// Calculates the next action for the entity
pub fn action(
    session: *const g.GameSession,
    entity: g.Entity,
    entity_place: p.Point,
    entity_speed: g.MovePoints,
    _: *c.Enemy,
    initiative: g.MovePoints,
) ?g.Action {
    const player_position = session.level.components.getForEntityUnsafe(session.level.player, c.Position);

    if (entity_place.near(player_position.point)) {
        if (session.level.components.getForEntity(entity, c.Weapon)) |weapon| {
            if (weapon.actualSpeed(entity_speed) > initiative) return null;
            const player_health = session.level.components.getForEntityUnsafe(session.level.player, c.Health);
            return .{ .hit = .{ .target = session.level.player, .target_health = player_health, .by_weapon = weapon } };
        }
    }
    if (entity_speed > initiative) return null;
    return .wait;
}
