const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

/// Optional replacements for the panel's left and right button behavior.
pub const ButtonOverrides = struct {
    /// A button label, borrowed context, and callback for one side.
    pub const Override = struct {
        button: w.Button,
        context: *anyopaque,
        handler: *const fn (context: *anyopaque, area: *anyopaque, is_helt: bool) anyerror!w.HandleButtonResult,
    };

    left: ?Override = null,
    right: ?Override = null,
};

/// Wraps an area with scrolling, a scrollbar, and contextual action buttons.
pub fn ScrollablePanel(comptime Area: type) type {
    return struct {
        const Self = @This();

        area: Area,
        region: p.Region,
        scrolled_lines: usize = 0,
        /// Overrides for the buttons of the area. Absent by default.
        button_overrides: ButtonOverrides = .{},

        /// Returns whether the content exceeds the visible region.
        pub fn isScrollRequired(self: *const Self) bool {
            return self.area.totalLines() > self.region.rows;
        }

        /// Returns the largest valid scroll offset.
        pub fn maxScrollingLines(self: *const Self) usize {
            return self.area.totalLines() -| self.region.rows;
        }

        /// Returns the number of content lines.
        pub fn totalLines(self: Self) usize {
            return self.area.totalLines();
        }

        /// Returns overridden buttons or delegates to the wrapped area.
        pub fn getButtons(self: *Self) w.Buttons {
            return .{
                .left = if (self.button_overrides.left) |override| override.button else self.area.getButtons().left,
                .right = if (self.button_overrides.right) |override| override.button else self.area.getButtons().right,
            };
        }

        /// Handles scrolling, overrides, and finally the wrapped area.
        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (try self.area.handleButton(btn) == .close_window) {
                return .close_window;
            }
            switch (btn.game_button) {
                .a, .b => {
                    const maybe_override = if (btn.game_button == .a)
                        self.button_overrides.right
                    else
                        self.button_overrides.left;
                    if (maybe_override) |override| {
                        return try override.handler(override.context, &self.area, btn.state == .hold);
                    }
                },
                .up => {
                    if (self.area.selectedLine()) |idx| {
                        // out of visible region
                        if (idx < self.scrolled_lines)
                            self.scrolled_lines -= 1;
                    }
                },
                .down => {
                    if (self.area.selectedLine()) |idx| {
                        // out of visible region
                        if (idx >= self.scrolled_lines + self.region.rows)
                            self.scrolled_lines += 1;
                    }
                },
                else => {},
            }
            return .keep_open;
        }

        /// Draws the scrollbar and the visible portion of the wrapped area.
        pub fn drawContent(self: *const Self, render: g.Render) !void {
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
            try self.area.drawContent(render, region.innerRegion(0, right_pad, 0, 0), scroll);
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
