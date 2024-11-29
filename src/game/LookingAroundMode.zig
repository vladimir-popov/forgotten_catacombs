//! This is a mode in which the player are able to look around the whole
//! dungeon.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.looking_around_mode);

const LookingAroundMode = @This();

session: *g.GameSession,
horizontal_step: u8,
vertical_step: u8,
orig_viewport_top_left: p.Point = undefined,

pub fn init(session: *g.GameSession) LookingAroundMode {
    return .{
        .session = session,
        .horizontal_step = session.viewport.region.cols / 5,
        .vertical_step = session.viewport.region.rows / 3,
    };
}

pub fn refresh(self: *LookingAroundMode) !void {
    self.orig_viewport_top_left = self.session.viewport.region.top_left;
    log.debug("Start looking around. Top-left corner of the viewport is {any}", .{self.orig_viewport_top_left});
    try self.draw();
}

pub fn tick(self: *LookingAroundMode) anyerror!void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a => {
                self.session.viewport.region.top_left = self.orig_viewport_top_left;
                log.debug(
                    "Stop looking around. Top-left corner of the viewport is {any}",
                    .{self.session.viewport.region.top_left},
                );
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
        try self.draw();
    }
}

fn draw(self: LookingAroundMode) !void {
    if (self.session.viewport.region.top_left.row > 1)
        self.session.viewport.setBorderWithArrow(.up);

    if (self.session.viewport.region.top_left.col > 1)
        self.session.viewport.setBorderWithArrow(.left);

    if (self.session.viewport.region.bottomRightRow() < g.Dungeon.ROWS)
        self.session.viewport.setBorderWithArrow(.down);

    if (self.session.viewport.region.bottomRightCol() < g.Dungeon.COLS)
        self.session.viewport.setBorderWithArrow(.right);

    try self.session.render.drawScene(self.session, null);
}
