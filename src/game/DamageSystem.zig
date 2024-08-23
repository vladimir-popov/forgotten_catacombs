const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const gm = @import("game.zig");

const log = std.log.scoped(.damage_system);

pub fn handleDamage(session: *gm.GameSession) anyerror!void {
    var itr = session.level.query().get2(gm.Damage, gm.Health);
    while (itr.next()) |components| {
        log.debug("The entity {d} received damage {d}", .{ components[0], components[1].amount });
        components[2].current -= @as(i16, @intCast(components[1].amount));
        try session.components.removeFromEntity(components[0], gm.Damage);
        try session.components.setToEntity(
            components[0],
            gm.Animation{ .frames = &gm.Animation.Presets.hit },
        );
        if (components[2].current <= 0) {
            log.debug("The entity {d} is died", .{components[0]});
            if (components[0] == session.player)
                try session.game.gameOver()
            else
                try session.level.removeEntity(components[0]);
        }
    }
}
