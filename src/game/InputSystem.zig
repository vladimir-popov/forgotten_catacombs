const std = @import("std");
const game = @import("game.zig");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

const log = std.log.scoped(.input_system);

pub fn handleInput(universe: *game.Universe) anyerror!void {
    const btn = try universe.runtime.readButton() orelse return;

    const now = universe.runtime.currentMillis();
    const timers = universe.getComponents(game.components.Timers)[0].timers;
    const timer = @intFromEnum(game.components.Timers.Handlers.input_system);
    const player_entity = universe.getComponents(game.components.Level)[0].player;
    if (universe.getComponent(player_entity, game.components.Move)) |move| {
        if (game.Button.isMove(btn)) {
            move.direction = if (btn & game.Button.Up > 0)
                p.Direction.up
            else if (btn & game.Button.Down > 0)
                p.Direction.down
            else if (btn & game.Button.Left > 0)
                p.Direction.left
            else
                p.Direction.right;
            move.keep_moving = now - timers[timer] < 200;
        }
    }
    timers[timer] = now;
}
