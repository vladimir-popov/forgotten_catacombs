const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.damage_system);

pub fn handleDamage(session: *g.GameSession) anyerror!void {
    var itr = session.level.query().get2(c.Damage, c.Health);
    while (itr.next()) |components| {
        log.debug("The entity {d} received damage {d}", .{ components[0], components[1].amount });
        components[2].current -= @as(i16, @intCast(components[1].amount));
        try session.level.components.removeFromEntity(components[0], c.Damage);
        try session.level.components.setToEntity(
            components[0],
            c.Animation{ .frames = &c.Animation.Presets.hit },
        );
        if (components[2].current <= 0) {
            log.debug("The entity {d} is died", .{components[0]});
            if (components[0] == session.level.player)
                try session.game.gameOver()
            else
                try session.level.removeEntity(components[0]);
        }
    }
}
