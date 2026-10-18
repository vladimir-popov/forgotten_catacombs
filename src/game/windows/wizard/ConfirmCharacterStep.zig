//! A wizard window that previews and confirms the completed character.
//!
//! ```
//! ╔════════════════════════════════════════╗
//! ║     Continue with this character?      ║
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
const AllocatorError = std.mem.Allocator.Error;

const PANEL_REGION: p.Region = .{
    .top_left = .{ .row = 3, .col = 2 },
    .rows = g.DISPLAY_ROWS - 2 - 2,
    .cols = g.DISPLAY_COLS - 1,
};

/// Creates the final character-preview step for the supplied context.
pub fn ConfirmCharacterStep(comptime Context: type) type {
    return struct {
        const Self = @This();

        context: *Context,
        panel: w.ScrollablePanel(w.TextArea),

        /// Builds the character summary from the shared context.
        pub fn init(
            self: *Self,
            alloc: std.mem.Allocator,
            context: *Context,
        ) (AllocatorError || std.fmt.BufPrintError)!void {
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

        /// Releases the summary text area.
        pub fn deinit(self: *Self) void {
            self.panel.deinit();
        }

        /// No additional work is required when the summary is accepted.
        pub fn commit(_: *Self) void {}

        /// No changes are made by this read-only step.
        pub fn rollback(_: *Self) void {}

        /// Returns the final `Play` button.
        pub fn getButtons(_: *Self) w.Buttons {
            return .{
                .right = .{ .label = "Play" },
            };
        }

        /// Handles scrolling and completion of the summary.
        pub fn handleButton(self: *Self, btn: g.Button) g.AllErrors!w.HandleButtonResult {
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

        /// Draws the character summary.
        pub fn drawContent(self: Self, render: g.Render) g.SystemError!void {
            try render.drawTextWithAlign(
                PANEL_REGION.cols,
                "Continue with this character?",
                .point(1, 1),
                .normal,
                .center,
            );
            try self.panel.drawContent(render);
        }
    };
}
