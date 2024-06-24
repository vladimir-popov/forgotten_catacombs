const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.collision_system);

pub fn handleCollisions(session: *game.GameSession) anyerror!void {
    for (session.components.getAll(game.Collision)) |collision| {
        switch (collision.obstacle) {
            .wall => {},
            .opened_door => try session.components.setToEntity(collision.entity, game.Action{ .close = collision.at }),
            .closed_door => try session.components.setToEntity(collision.entity, game.Action{ .open = collision.at }),
            .entity => |entity| {
                if (session.components.getForEntity(collision.entity, game.Health)) |_| {
                    if (session.components.getForEntity(entity, game.Health)) |_| {
                        try session.components.setToEntity(collision.entity, game.Action{ .hit = entity });
                    }
                }
            },
        }
    }
    try session.components.removeAll(game.Collision);
}
