const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collision_system);

pub fn handleCollisions(session: *game.GameSession) anyerror!void {
    for (session.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .door => |door| try session.components.setToEntity(
                collision.entity,
                if (door.state == .closed)
                    game.Action{ .open = door.entity }
                else
                    game.Action{ .close = door.entity },
            ),
            .enemy => |enemy| {
                if (session.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (session.components.getForEntity(enemy, game.Health)) |_| {
                        try session.components.setToEntity(collision.entity, game.Action{ .hit = enemy });
                    }
                }
            },
            .item => {},
        }
    }
    try session.components.removeAll(game.Collision);
}
