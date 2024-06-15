const std = @import("std");
const game = @import("game.zig");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const log = std.log.scoped(.input_system);

pub fn handleInput(session: *game.GameSession) anyerror!void {
    const btn = try session.runtime.readButton();
    if (btn == 0) return;

    const now = session.runtime.currentMillis();
    const timer = session.timer(game.GameSession.Timers.input_system);
    if (session.components.getForEntity(session.player, game.Move)) |move| {
        if (game.AnyRuntime.Button.toDirection(btn)) |direction| {
            move.direction = direction;
            move.keep_moving = now - timer.* < 200;
        }
    }
    timer.* = now;
}
