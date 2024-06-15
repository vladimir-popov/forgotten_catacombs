const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");
const cmp = game.components;

pub fn render(session: *game.GameSession) anyerror!void {
    const screen = &session.screen;
    try session.runtime.drawDungeon(screen, session.dungeon);

    for (session.positions.components.items) |*position| {
        if (screen.region.containsPoint(position.point)) {
            for (session.sprites.components.items) |*sprite| {
                try session.runtime.drawSprite(screen, sprite, position);
            }
        }
    }
}
