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

        pub fn init(content: Area, region: p.Region) Self {
            return .{ .content = content, .region = region };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.content.deinit(alloc);
        }

        pub fn isScrollRequired(self: Self) bool {
            return self.content.totalLines() > self.region.rows;
        }

        fn maxScrollingCount(self: Self) usize {
            return self.content.totalLines() -| (self.region.rows);
        }

        /// Returns a label for the right button handled by the content,
        /// or null if the content doesn't handle the right button.
        pub fn button(self: Self) ?struct { []const u8, bool } {
            return self.content.button();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !bool {
            if (try self.content.handleButton(btn))
                return true;

            if (!self.isScrollRequired()) return false;
            if (self.content.selectedLine()) |selected_line| {
                if (self.region.rows + self.scrolled_lines > selected_line and selected_line >= self.scrolled_lines)
                    return false;
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
            return false;
        }

        pub fn draw(self: *const Self, render: g.Render) !void {
            // Draw the scrollbar
            if (self.isScrollRequired()) {
                const progress = w.scrollingProgress(self.scrolled_lines, self.region.rows, self.maxScrollingCount());
                log.debug(
                    "Drawing the scroll bar. Scrolled lines {d}; progress {d}; total lines {d}",
                    .{ self.scrolled_lines, progress, self.content.totalLines() },
                );
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
    };
}
