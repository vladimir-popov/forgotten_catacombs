const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.damage_system);

pub fn handleDamage(session: *game.GameSession) anyerror!void {
    var itr = session.query.get3(game.Damage, game.Health, game.Sprite);
    while (itr.next()) |components| {
        log.debug("The entity {d} received damage {d}", .{components[0], components[1].amount});
        components[2].current -= @as(i16, @intCast(components[1].amount));
        try session.components.removeFromEntity(components[0], game.Damage);
        try session.components.setToEntity(
            components[0],
            game.Animation{ .frames = &game.Animation.Presets.hit },
        );
        if (components[2].current <= 0) {
            log.debug("The entity {d} is died", .{components[0]});
            try session.removeEntity(components[0]);
        }
    }
}
