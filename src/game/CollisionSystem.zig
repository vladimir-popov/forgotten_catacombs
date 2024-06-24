const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collisions);

pub fn handleCollisions(session: *game.GameSession) anyerror!void {
    for (session.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .opened_door => try session.components.setToEntity(collision.entity, game.Action{ .close = collision.at }),
            .closed_door => try session.components.setToEntity(collision.entity, game.Action{ .open = collision.at }),
            .entity => |entity| {
                if (session.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (session.components.getForEntity(entity, game.Health)) |_| {
                        if (session.runtime.rand.boolean()) {
                            try session.components.setToEntity(
                                entity,
                                game.Damage{
                                    .entity = entity,
                                    .amount = session.runtime.rand.uintLessThan(u8, 3) + 1,
                                },
                            );
                        } else {
                            try session.components.setToEntity(
                                entity,
                                game.Animation{
                                    .frames = &game.Animation.Presets.miss,
                                    .position = collision.at,
                                },
                            );
                        }
                    }
                }
            },
        }
    }
    try session.components.removeAll(game.Collision);
}
