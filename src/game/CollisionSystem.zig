const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.collision_system);

pub fn handleCollisions(session: *g.GameSession) anyerror!void {
    for (session.level.components.getAll(c.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .door => |door| try session.level.components.setToEntity(
                collision.entity,
                c.Action{ .type = .{ .open = door.entity }, .move_points = 10 },
            ),
            .enemy => |enemy| {
                if (session.level.components.getForEntity(collision.entity, c.Health)) |_| {
                    if (session.level.components.getForEntity(enemy, c.Health)) |_| {
                        if (session.level.components.getForEntity(session.player, c.MeleeWeapon)) |weapon| {
                            try session.level.components.setToEntity(
                                collision.entity,
                                c.Action{ .type = .{ .hit = enemy }, .move_points = weapon.move_points },
                            );
                        }
                    }
                }
            },
            .item => {},
        }
    }
    try session.level.components.removeAll(c.Collision);
}
