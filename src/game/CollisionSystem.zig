const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collision_system);

pub fn handleCollisions(play_mode: *game.PlayMode) anyerror!void {
    for (play_mode.session.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .door => |door| try play_mode.session.components.setToEntity(
                collision.entity,
                if (door.state == .closed)
                    game.Action{ .open = door.entity }
                else
                    game.Action{ .close = door.entity },
            ),
            .enemy => |enemy| {
                if (play_mode.session.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (play_mode.session.components.getForEntity(enemy, game.Health)) |_| {
                        try play_mode.session.components.setToEntity(collision.entity, game.Action{ .hit = enemy });
                    }
                }
            },
            .item => {},
        }
    }
    try play_mode.session.components.removeAll(game.Collision);
}
