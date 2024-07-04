const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const log = std.log.scoped(.pause_mode);

const PauseMode = @This();

session: *game.GameSession,
target: game.Entity,

pub fn init(session: *game.GameSession) PauseMode {
    return .{ .session = session, .target = session.player };
}

pub fn handleInput(self: *PauseMode, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => {},
        game.Buttons.B => {
            self.session.play();
        },
        game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
            self.chooseNextEntity(buttons.toDirection().?);
        },
        else => {},
    }
}

pub fn draw(pause_mode: PauseMode) !void {
    try pause_mode.session.runtime.drawLabel("pause", .{ .row = 1, .col = game.DISPLAY_DUNG_COLS + 2 });
}

pub fn update(self: *PauseMode) anyerror!void {
    _ = self;
}

fn chooseNextEntity(self: *PauseMode, direction: p.Direction) void {
    _ = self;
    _ = direction;
}
