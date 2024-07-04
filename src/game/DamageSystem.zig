const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const log = std.log.scoped(.damage_system);

pub fn handleDamage(play_mode: *game.PlayMode) anyerror!void {
    var itr = play_mode.session.query.get3(game.Damage, game.Health, game.Sprite);
    while (itr.next()) |components| {
        components[2].hp -= @as(i16, @intCast(components[1].amount));
        try play_mode.session.components.removeFromEntity(components[0], game.Damage);
        try play_mode.session.components.setToEntity(
            components[0],
            game.Animation{ .frames = &game.Animation.Presets.hit, .position = components[3].position },
        );
        if (components[2].hp <= 0) {
            try play_mode.session.removeEntity(components[0]);
        }
    }
}
