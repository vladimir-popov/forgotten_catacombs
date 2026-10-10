const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

/// Wraps an area with scrolling, a scrollbar, and contextual action buttons.
pub fn ScrollablePanel(comptime Area: type) type {
    return struct {
        const Self = @This();

        area: Area,
        region: p.Region,
        scrolled_lines: usize = 0,

        pub fn isScrollRequired(self: *const Self) bool {
            return self.area.totalLines() > self.region.rows;
        }

        pub fn maxScrollingLines(self: *const Self) usize {
            return self.area.totalLines() -| self.region.rows;
        }

        pub fn totalLines(self: Self) usize {
            return self.area.totalLines();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !void {
            try self.areahandleButton(btn);
            switch (btn.game_button) {
                .up => {
                    if (self.scrolled_lines > 0)
                        self.scrolled_lines -= 1;
                },
                .down => {
                    if (self.scrolled_lines < self.maxScrollingLines())
                        self.scrolled_lines += 1;
                },
                else => {},
            }
        }

        pub fn draw(self: *const Self, render: g.Render) !void {
            const region = self.region;
            const max_scroll_count = self.maxScrollingLines();
            const scroll = @min(self.scrolled_lines, max_scroll_count);

            // Draw the scrollbar
            if (self.isScrollRequired()) {
                const progress = scrollingProgress(scroll, region.rows, max_scroll_count);
                var point = region.topRight();
                for (0..region.rows) |i| {
                    if (i == progress)
                        try render.runtime.drawSprite('▒', point, .normal)
                    else
                        try render.runtime.drawSprite('░', point, .normal);
                    point.move(.down);
                }
            }
            // Draw the content inside the region excluding a space for the scrollbar
            const right_pad: u8 = if (self.isScrollRequired()) 1 else 0;
            try self.area.draw(render, region.innerRegion(0, right_pad, 0, 0), scroll);
        }

        fn scrollingProgress(scrolled_lines: usize, area_height: usize, max_scroll_count: usize) usize {
            if (area_height == 0 or max_scroll_count == 0) return 0;

            const safe_scrolled_lines = @min(scrolled_lines, max_scroll_count);
            var progress = safe_scrolled_lines * area_height / max_scroll_count;
            if (progress == 0 and scrolled_lines > 0) progress += 1;
            if (progress == area_height - 1 or progress == area_height)
                progress -= 1;
            return progress;
        }
    };
}
