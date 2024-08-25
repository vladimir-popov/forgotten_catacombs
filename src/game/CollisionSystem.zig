const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collision_system);

pub fn handleCollisions(session: *game.GameSession) anyerror!void {
    for (session.level.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .door => |door| try session.level.components.setToEntity(
                collision.entity,
                game.Action{ .type = .{ .open = door.entity }, .move_points = 10 },
            ),
            .enemy => |enemy| {
                if (session.level.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (session.level.components.getForEntity(enemy, game.Health)) |_| {
                        if (session.level.components.getForEntity(session.player, game.MeleeWeapon)) |weapon| {
                            try session.level.components.setToEntity(
                                collision.entity,
                                game.Action{ .type = .{ .hit = enemy }, .move_points = weapon.move_points },
                            );
                        }
                    }
                }
            },
            .item => {},
        }
    }
    try session.level.components.removeAll(game.Collision);
}
