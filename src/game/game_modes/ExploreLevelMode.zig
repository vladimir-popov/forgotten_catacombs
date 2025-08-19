//! This is a mode in which the player are able to explore the whole dungeon.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.explore_level_mode);

const ExploreLevelMode = @This();

session: *g.GameSession,
horizontal_step: u8,
vertical_step: u8,
orig_viewport_top_left: p.Point,

pub fn init(session: *g.GameSession) !ExploreLevelMode {
    log.debug("Init ExploreLevelMode", .{});
    try draw(session);
    return .{
        .session = session,
        .horizontal_step = session.viewport.region.cols / 5,
        .vertical_step = session.viewport.region.rows / 3,
        .orig_viewport_top_left = session.viewport.region.top_left,
    };
}

fn draw(session: *g.GameSession) !void {
    try session.render.hideLeftButton();
    try session.render.drawInfo("Explore the level");
    try session.render.drawRightButton("Cancel", false);
    if (session.viewport.region.top_left.row > 1)
        session.render.setBorderWithArrow(session.viewport, .up);

    if (session.viewport.region.top_left.col > 1)
        session.render.setBorderWithArrow(session.viewport, .left);

    if (session.viewport.region.bottomRightRow() < g.DUNGEON_ROWS)
        session.render.setBorderWithArrow(session.viewport, .down);

    if (session.viewport.region.bottomRightCol() < g.DUNGEON_COLS)
        session.render.setBorderWithArrow(session.viewport, .right);

    try session.render.drawScene(session, null);
}

pub fn tick(self: *ExploreLevelMode) anyerror!void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a => {
                self.session.viewport.region.top_left = self.orig_viewport_top_left;
                try self.session.continuePlay(null, null);
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
        try draw(self.session);
    }
}
