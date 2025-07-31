//! A pop up window placed in the middle of the screen above info bar.
//! It has fixed width and dynamic hight that depends on number of lines
//! in the aria with content.
//!
//! The Modal window always has 'Close' button, and may have an optional button
//! provided by the area.
//!
//! If the area has more lines than the region of the window, the scrollbar is drawn.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

pub fn ModalWindow(comptime Area: type) type {
    return struct {
        const Self = @This();

        area: Area,
        title: []const u8 = "",
        scrolled_lines: usize = 0,

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.area.deinit(alloc);
        }

        /// Returns the region that should be occupied (including borders)
        /// according to the number of actual rows in the area.
        fn region(self: Self) p.Region {
            // Count of rows that should be drawn (including border)
            const rows: usize = self.area.totalLines() + 2; // 2 for border
            return .{
                .top_left = if (rows < w.MAX_REGION.rows)
                    w.MAX_REGION.top_left.movedToNTimes(.down, (w.MAX_REGION.rows - rows) / 2)
                else
                    w.MAX_REGION.top_left,
                .rows = @min(rows, w.MAX_REGION.rows),
                .cols = w.MAX_REGION.cols,
            };
        }

        pub fn isScrolled(self: Self) bool {
            const content_lines = self.area.totalLines();
            return content_lines + 2 > w.MAX_REGION.rows;
        }

        /// Returns true if the 'close' button was pressed.
        pub fn handleButton(self: *Self, btn: g.Button) !bool {
            try self.area.handleButton(btn);
            switch (btn.game_button) {
                // pressing the right button is always lead to closing the window
                .a => return true,
                // if the aria has a special handler for the right button, then
                // the left is 'Close' button
                .b => return self.area.button() != null,
                .up, .down => self.scrollingUpOrDown(btn.game_button == .up),
                else => {},
            }
            return false;
        }

        fn scrollingUpOrDown(self: *Self, scrolling_up: bool) void {
            if (!self.isScrolled()) return;

            // this doesn't work with OptionsArea, but combination of the ModalWindow
            // and an OptionsArea never have many lines.
            if (scrolling_up) {
                if (self.scrolled_lines > 0)
                    self.scrolled_lines -= 1;
            } else if (self.scrolled_lines < self.maxScrollingCount()) {
                self.scrolled_lines += 1;
            }
        }

        inline fn maxScrollingCount(self: Self) usize {
            return self.area.totalLines() - (w.MAX_REGION.rows - 2); // -2 borders
        }

        pub fn draw(self: *const Self, render: g.Render) !void {
            const reg = self.region();
            const total_lines = self.area.totalLines();

            log.debug("Drawing modal window in region {any}", .{reg});
            // Draw the border
            try render.drawBorder(reg);
            // Draw the title
            const padding: u8 = @intCast(reg.cols - self.title.len);
            var point = reg.top_left.movedToNTimes(.right, padding / 2);
            for (self.title) |char| {
                try render.runtime.drawSprite(char, point, .normal);
                point.move(.right);
            }
            // Draw the scrollbar
            if (self.isScrolled()) {
                const progress = w.scrollingProgress(self.scrolled_lines, reg.rows - 2, self.maxScrollingCount());
                log.debug(
                    "Drawing scroll bar. Scrolled lines {d}; progress {d}; total lines {d}",
                    .{ self.scrolled_lines, progress, total_lines },
                );
                point = reg.topRight().movedTo(.left);
                for (0..reg.rows - 2) |i| {
                    point.move(.down);
                    if (i == progress)
                        try render.runtime.drawSprite('▒', point, .normal)
                    else
                        try render.runtime.drawSprite('░', point, .normal);
                }
            }
            // Draw the content inside the region excluding borders and space for scrollbar
            const right_pad: u8 = if (self.isScrolled()) 2 else 1;
            try self.area.draw(render, reg.innerRegion(1, right_pad, 1, 1), self.scrolled_lines);
            // Draw buttons
            if (self.area.button()) |button| {
                try render.drawRightButton(button[0], button[1]);
                try render.drawLeftButton("Close", false);
            } else {
                try render.drawRightButton("Close", false);
                try render.hideLeftButton();
            }
        }

        pub fn hide(self: *Self, render: g.Render, hide_mode: w.HideMode) !void {
            log.debug("Hide modal window", .{});
            switch (hide_mode) {
                .from_buffer => try render.redrawRegionFromSceneBuffer(self.region()),
                .fill_region => try render.fillRegion(' ', .normal, self.region()),
            }
        }
    };
}
