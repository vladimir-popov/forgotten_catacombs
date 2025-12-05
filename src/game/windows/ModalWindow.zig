//! A pop up window placed in the middle of the screen above info bar.
//! It has fixed width and dynamic hight that depends on a number of lines
//! in the content aria.
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

/// A maximal region which can be occupied by the modal window.
/// This region includes a space for borders.
const DEFAULT_MAX_REGION: p.Region = p.Region.init(1, 2, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS - 2);

pub fn ModalWindow(comptime Area: type) type {
    return struct {
        const Self = @This();

        title_buffer: [32]u8 = undefined,
        title_len: usize = 0,
        content: w.ScrollableAre(Area),
        /// An actual region occupied by this window (including borders)
        region: p.Region,

        pub inline fn default(content: Area) Self {
            return init(content, DEFAULT_MAX_REGION);
        }

        pub fn init(content: Area, max_region: p.Region) Self {
            const region = calculateOccupiedRegion(content, max_region);
            return .{ .content = .init(content, region.innerRegion(1, 1, 1, 1)), .region = region };
        }

        fn calculateOccupiedRegion(content: Area, max_region: p.Region) p.Region {
            // Count of rows that should be drawn (including border)
            const rows: usize = content.totalLines() + 2; // 2 for border
            return .{
                .top_left = if (rows < max_region.rows)
                    max_region.top_left.movedToNTimes(.down, (max_region.rows - rows) / 2)
                else
                    max_region.top_left,
                .rows = @min(rows, max_region.rows),
                .cols = max_region.cols,
            };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.content.deinit(alloc);
        }

        inline fn title(self: Self) []const u8 {
            return self.title_buffer[0..self.title_len];
        }

        /// Returns true if the 'close' button was pressed.
        pub fn handleButton(self: *Self, btn: g.Button) !bool {
            try self.content.handleButton(btn);
            switch (btn.game_button) {
                // pressing the right button is always lead to closing the window
                .a => return true,
                // if the aria has a special handler for the right button, then
                // the left is 'Close' button
                .b => return self.content.button() != null,
                else => {},
            }
            return false;
        }

        /// Draws the window with a scrollbar and buttons if they are required.
        /// The `Close` button is drawn on the right if the area doesn't provide
        /// an additional button, and on the left otherwise.
        pub fn draw(self: *const Self, render: g.Render) !void {
            log.debug("Drawing modal window in the region {any}", .{self.region});
            // Draw the border
            try render.drawBorder(self.region);
            // Draw the title
            const padding: u8 = @intCast(self.region.cols - self.title_len);
            var point = self.region.top_left.movedToNTimes(.right, padding / 2);
            for (self.title()) |char| {
                try render.runtime.drawSprite(char, point, .normal);
                point.move(.right);
            }
            // Draw the content
            try self.content.draw(render);
            // Draw buttons
            if (self.content.button()) |button| {
                try render.drawRightButton(button[0], button[1]);
                try render.drawLeftButton("Close", false);
            } else {
                try render.drawRightButton("Close", false);
                try render.hideLeftButton();
            }
        }

        /// Fills the region of the window or from the buffer, or just fill it with spaces.
        pub fn hide(self: *Self, render: g.Render, hide_mode: w.HideMode) !void {
            log.debug("Hide a modal window", .{});
            switch (hide_mode) {
                .from_buffer => try render.redrawRegionFromSceneBuffer(self.region),
                .fill_region => try render.fillRegion(' ', .normal, self.region),
            }
        }
    };
}
