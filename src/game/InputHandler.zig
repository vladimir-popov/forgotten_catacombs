const std = @import("std");
const game = @import("game.zig");

const log = std.log.scoped(.input);

pub fn handleInput(session: *game.GameSession, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => if (session.state == .play) {
            var quick_action: game.Action = .wait;
            if (session.entity_in_focus) |e| {
                if (e.quick_action) |qa| quick_action = qa;
            }
            try session.components.setToEntity(session.player, quick_action);
        },
        game.Buttons.B => {
            session.state = if (session.state == .play) .pause else .play;
        },
        game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
            if (session.state == .pause) {
                session.chooseNextEntity();
            } else {
                try session.components.setToEntity(session.player, game.Action{
                    .move = .{
                        .direction = buttons.toDirection().?,
                        .keep_moving = false, // btn.state == .double_pressed,
                    },
                });
            }
        },
        else => {},
    }
}
