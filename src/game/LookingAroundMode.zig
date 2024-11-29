//! This is a mode in which the player are able to look around the whole
//! dungeon.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const LookingAroundMode = @This();

session: *g.GameSession,
orig_viewport_top_left: p.Point,
horizontal_step: u8,
vertical_step: u8,

pub fn init(session: *g.GameSession) LookingAroundMode {
    return .{
        .session = session,
        .orig_viewport_top_left = session.viewport.region.top_left,
        .horizontal_step = session.viewport.region.cols / 3,
        .vertical_step = session.viewport.region.rows / 3,
    };
}

pub fn tick(self: *LookingAroundMode) anyerror!void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a, .b => {
                self.session.viewport.region.top_left = self.orig_viewport_top_left;
                try self.session.play(null);
                return;
            },
            .left, .right => {
                self.session.viewport.moveNTimes(btn.toDirection().?, self.horizontal_step);
            },
            .up, .down => {
                self.session.viewport.moveNTimes(btn.toDirection().?, self.vertical_step);
            },
            else => {},
        }
        try self.session.render.drawScene(self.session, null);
    }
}
