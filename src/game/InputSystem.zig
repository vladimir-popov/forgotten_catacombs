const std = @import("std");
const game = @import("game.zig");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const log = std.log.scoped(.input_system);

pub fn handleInput(universe: *game.Universe) anyerror!void {
    const btn = try universe.runtime.readButton();
    if (btn == 0) return;

    const now = universe.runtime.currentMillis();
    const timer = universe.root.timer(game.GameSession.Timers.input_system);
    if (universe.getComponent(universe.root.player, game.components.Move)) |move| {
        if (game.Button.toDirection(btn)) |direction| {
            move.direction = direction;
            move.keep_moving = now - timer.* < 200;
        }
    }
    timer.* = now;
}
