const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

/// The aria provides scrolling functionality to another inner aria.
pub fn ScrollableArea(comptime Area: type) type {
    return struct {
        const Self = @This();

        content: Area,
        region: p.Region,
        scrolled_lines: usize = 0,

        pub fn area(self: *Self) w.Area {
            return .{ .underlying = self, .vtable = w.Area.vtableFor(Self) };
        }

        pub fn isScrollRequired(self: *const Self) bool {
            return self.content.totalLines() > self.region.rows;
        }

        fn maxScrollingCount(self: *const Self) usize {
            return self.content.totalLines() -| (self.region.rows);
        }

        pub fn totalLines(self: Self) usize {
            return self.content.totalLines();
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.content.clearRetainingCapacity();
        }

        pub fn leftButton(self: *const Self) ?w.Button {
            return self.content.leftButton();
        }

        pub fn rightButton(self: *const Self) ?w.Button {
            return self.content.rightButton();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (try self.content.handleButton(btn) == .close_window)
                return .close_window;

            if (!self.isScrollRequired()) return .keep_open;
            if (self.content.selectedLine()) |selected_line| {
                if (self.region.rows + self.scrolled_lines > selected_line and selected_line >= self.scrolled_lines)
                    return .keep_open;
            }

            switch (btn.game_button) {
                .up => {
                    if (self.scrolled_lines > 0)
                        self.scrolled_lines -= 1;
                },
                .down => {
                    if (self.scrolled_lines < self.maxScrollingCount())
                        self.scrolled_lines += 1;
                },
                else => {},
            }
            return .keep_open;
        }

        pub fn draw(self: *const Self, render: g.Render) !void {
            // Draw the scrollbar
            if (self.isScrollRequired()) {
                const progress = scrollingProgress(self.scrolled_lines, self.region.rows, self.maxScrollingCount());
                var point = self.region.topRight();
                for (0..self.region.rows) |i| {
                    if (i == progress)
                        try render.runtime.drawSprite('▒', point, .normal)
                    else
                        try render.runtime.drawSprite('░', point, .normal);
                    point.move(.down);
                }
            }
            // Draw the content inside the region excluding a space for the scrollbar
            const right_pad: u8 = if (self.isScrollRequired()) 1 else 0;
            try self.content.draw(render, self.region.innerRegion(0, right_pad, 0, 0), self.scrolled_lines);
        }

        fn scrollingProgress(scrolled_lines: usize, area_height: usize, max_scroll_count: usize) usize {
            var progress = scrolled_lines * area_height / max_scroll_count;
            // Two corner cases for better UX:
            // 1. Move the scroll after the first scrolling
            if (progress == 0 and scrolled_lines > 0) progress += 1;
            // 2. Do not move the scroll to the end until the last possible line is scrolled
            // (progress become == content_height)
            if (progress == area_height - 1 or progress == area_height)
                progress -= 1;
            return progress;
        }
    };
}
