const std = @import("std");
const algs = @import("algs_and_types");
const p = algs.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.ai);

pub fn doMove(play_mode: *game.PlayMode) anyerror!void {
    var itr = play_mode.session.query.get3(game.Sprite, game.Health, game.MovePoints);
    while (itr.next()) |components| {
        const entity = components[0];
        if (entity == play_mode.session.player) continue;
        const sprite = components[1];
        const health = components[2];
        const move_points = components[3];
        if (nextAction(play_mode.session, entity, sprite.position, health, move_points)) |action|
            try play_mode.session.components.setToEntity(entity, action);
    }
}

fn nextAction(
    session: *game.GameSession,
    entity: game.Entity,
    entity_position: p.Point,
    _: *const game.Health,
    move_points: *const game.MovePoints,
) ?game.Action {
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    if (entity_position.near(player_position)) {
        const weapon = session.components.getForEntityUnsafe(entity, game.MeleeWeapon);
        if (move_points.count >= weapon.move_points) {
            return .{ .type = .{ .hit = session.player }, .move_points = weapon.move_points };
        }
    } else {
        return .{ .type = .wait, .move_points = move_points.speed };
    }
    return null;
}
