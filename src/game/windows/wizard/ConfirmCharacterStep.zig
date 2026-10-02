//! ```
//! ╔════════════════════════════════════════╗
//! ║       Start with this character?       ║
//! ║  ┌                                     ║
//! ║   Level: {d}                          ▒║
//! ║   Experience: {d}/{d}                 ░║
//! ║                                       ░║
//! ║   Health: 30/30                       ░║
//! ║                                       ░║
//! ║   Skills:                             ░║
//! ║     Weapon Mastery:     2             ░║
//! ║     Mechanics           0             ░║
//! ║════════════════════════════════════════║
//! ║                               Play     ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const PANEL_REGION: p.Region = .{
    .top_left = .{ .row = 3, .col = 2 },
    .rows = g.DISPLAY_ROWS - 2 - 2,
    .cols = g.DISPLAY_COLS - 1,
};

pub fn ConfirmCharacterStep(comptime Context: type) type {
    return struct {
        const Self = @This();

        context: *Context,
        panel: w.ScrollablePanel(w.TextArea),

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.context = context;
            self.panel = .{ .area = .initEmpty(alloc), .region = PANEL_REGION };
            self.context.health = g.meta.initialHealth(self.context.stats.get(.constitution));
            const text_area = &self.panel.area;
            try g.Description.describeProgression(1, 0, text_area);
            _ = try text_area.addEmptyLine();
            try g.Description.describeHealth(&self.context.health, text_area);
            _ = try text_area.addEmptyLine();
            try g.Description.describeSkills(&self.context.skills, text_area);
            _ = try text_area.addEmptyLine();
            try g.Description.describeStats(&self.context.stats, text_area);
        }

        pub fn deinit(self: *Self) void {
            self.panel.deinit();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            switch (btn.game_button) {
                .a => {
                    return .close_window;
                },
                .up, .down => {
                    _ = try self.panel.handleButton(btn);
                },
                else => {},
            }
            return .keep_open;
        }

        pub fn draw(self: Self, render: g.Render) !void {
            try render.drawTextWithAlign(
                PANEL_REGION.cols,
                "Start with this character?",
                .point(1, 1),
                .normal,
                .center,
            );
            try self.panel.draw(render);
            try render.cleanInfo();
            try render.drawRightButton("Play", false);
        }
    };
}
