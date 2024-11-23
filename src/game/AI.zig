const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

/// Calculates the next action for the entity
pub fn action(session: *const g.GameSession, entity: g.Entity) c.Action {
    // here check if the entity still exists
    const entity_position = session.level.components.getForEntityUnsafe(entity, c.Position);
    const player_position = session.level.components.getForEntityUnsafe(session.level.player, c.Position);

    if (entity_position.point.near(player_position.point)) {
        const weapon = session.level.components.getForEntityUnsafe(entity, c.MeleeWeapon);
        return .{ .type = .{ .hit = session.level.player }, .move_points = weapon.move_points };
    }
    const entity_speed = session.level.components.getForEntityUnsafe(entity, c.Speed);
    return .{ .type = .wait, .move_points = entity_speed.move_points };
}
