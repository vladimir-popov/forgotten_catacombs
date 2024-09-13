const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.ai);

pub fn meleeMove(session: *g.GameSession, entity: g.Entity, available_move_points: u8) anyerror!u8 {
    // here check if the entity still exists
    if (session.level.components.getForEntity(entity, c.Position)) |position| {
        const action = nextAction(session, entity, position, available_move_points);
        try session.level.components.setToEntity(entity, action);
        return action.move_points;
    } else {
        return 0;
    }
}

fn nextAction(
    session: *g.GameSession,
    entity: g.Entity,
    entity_position: *const c.Position,
    available_move_points: u8,
) c.Action {
    const player_position = session.level.components.getForEntityUnsafe(session.level.player, c.Position);
    if (entity_position.point.near(player_position.point)) {
        const weapon = session.level.components.getForEntityUnsafe(entity, c.MeleeWeapon);
        if (available_move_points >= weapon.move_points) {
            return .{ .type = .{ .hit = session.level.player }, .move_points = weapon.move_points };
        }
    }
    // wait should always take all available move points
    return .{ .type = .wait, .move_points = 0 };
}
