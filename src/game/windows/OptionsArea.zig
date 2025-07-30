//! This is an area with a list of options.
//! Options with items and right button handlers can be added. An appropriate handler will be
//! invoked inside the `handleButton` method. The owner, index of the current line and appropriate item
//! will be passed to the handler.
//! ```
//!  ┌────────────────────────────────────┐
//!  │             option 1               │
//!  │░░░░░░░░░░░░░option░2░░░░░░░░░░░░░░░│
//!  │             option 3               │
//!  └────────────────────────────────────┘
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const LINE_BUFFER_SIZE = g.DISPLAY_COLS;

pub fn OptionsArea(comptime Item: type) type {
    return struct {
        const Self = @This();

        pub const OnReleaseButton = *const fn (
            owner: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!void;

        pub const OnHoldButton = *const fn (
            owner: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!void;

        pub const Option = struct {
            item: Item,
            label_buffer: [LINE_BUFFER_SIZE]u8,
            label_len: usize,
            onReleaseButtonFn: OnReleaseButton,
            onHoldButtonFn: ?OnHoldButton,

            pub fn label(self: *const @This()) []const u8 {
                return self.label_buffer[0..self.label_len];
            }
        };

        /// The owner is always passed to button handlers
        owner: *anyopaque,
        options: std.ArrayListUnmanaged(Option),
        text_align: g.TextAlign,
        /// The absolute index of the selected line (includes the lines out of scroll)
        selected_line: usize = 0,

        pub fn init(
            owner: *anyopaque,
            text_align: g.TextAlign,
        ) Self {
            return .{
                .owner = owner,
                .text_align = text_align,
                .options = .empty,
            };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.options.deinit(alloc);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.options.clearRetainingCapacity();
            self.selected_line = 0;
        }

        pub fn totalLines(self: Self) usize {
            return self.options.items.len;
        }

        pub fn button(self: Self) ?struct { []const u8, bool } {
            if (self.options.items.len > 0) {
                const option = self.options.items[self.selected_line];
                return .{ "Choose", option.onHoldButtonFn != null };
            } else {
                return null;
            }
        }

        pub fn addOption(
            self: *Self,
            alloc: std.mem.Allocator,
            label: []const u8,
            item: Item,
            onReleaseButtonFn: OnReleaseButton,
            onHoldButtonFn: ?OnHoldButton,
        ) !void {
            std.debug.assert(label.len < LINE_BUFFER_SIZE);

            const line = try self.options.addOne(alloc);
            line.* = .{
                .item = item,
                .label_len = label.len,
                .label_buffer = undefined,
                .onReleaseButtonFn = onReleaseButtonFn,
                .onHoldButtonFn = onHoldButtonFn,
            };
            @memmove(line.label_buffer[0..line.label_len], label);
        }

        pub fn selectLine(self: *Self, idx: usize) !void {
            std.debug.assert(idx < self.options.items.len);
            self.selected_line = idx;
        }

        pub fn selectPreviousLine(self: *Self) void {
            if (self.selected_line > 0)
                self.selected_line -= 1
            else
                self.selected_line = self.options.items.len - 1;
        }

        pub fn selectNextLine(self: *Self) void {
            if (self.selected_line < self.options.items.len - 1)
                self.selected_line += 1
            else
                self.selected_line = 0;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !void {
            switch (btn.game_button) {
                .up => self.selectPreviousLine(),
                .down => self.selectNextLine(),
                .a => {
                    const option = self.options.items[self.selected_line];
                    if (btn.state == .hold and option.onHoldButtonFn != null) {
                        try option.onHoldButtonFn.?(self.owner, self.selected_line, option.item);
                    } else {
                        try option.onReleaseButtonFn(self.owner, self.selected_line, option.item);
                    }
                },
                else => {},
            }
        }

        /// Draws the options line by line inside the passed region. If the region has not enough
        /// rows, then the options will be scrolled. If the region has not enough columns, then
        /// the label will be cropped.
        ///
        /// - `region` - A region where this aria should be drawn. For left aligned text the first
        /// symbol will be drawn at the top left corner of the passed region.
        ///
        /// - `scrolled` - How many scrolled lines should be skipped.
        pub fn draw(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) !void {
            log.debug(
                "Draw {d} options inside {any}; Scrolled lines {d}; Selected line is {any};",
                .{ self.options.items.len, region, scrolled, self.selected_line },
            );
            for (0..region.rows) |row_idx| {
                var point = region.top_left.movedToNTimes(.down, row_idx);
                if (row_idx + scrolled < self.options.items.len) {
                    const label = self.options.items[row_idx + scrolled].label();
                    const mode: g.DrawingMode = if (self.selected_line == row_idx) .inverted else .normal;
                    const pad = switch (self.text_align) {
                        .left => 0,
                        .center => p.diff(u8, region.cols, @min(region.cols, label.len)) / 2,
                        .right => p.diff(u8, region.cols, @min(region.cols, label.len)),
                    };
                    for (0..region.cols) |col_idx| {
                        if (col_idx < pad or col_idx >= pad + label.len)
                            try render.drawSymbol(' ', point, mode)
                        else
                            try render.drawSymbol(label[col_idx - pad], point, mode);

                        point.move(.right);
                    }
                } else {
                    try render.drawHorizontalLine(' ', point, region.cols);
                }
            }
        }
    };
}
