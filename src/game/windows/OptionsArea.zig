const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const LINE_BUFFER_SIZE = g.DISPLAY_COLS;

/// This is an area with a list of options.
/// Options with items and right button handlers can be added. An appropriate handler will be
/// invoked inside the `handleButton` method. The owner, index of the current line and appropriate item
/// will be passed to the handler.
/// ```
///  ┌────────────────────────────────────┐
///  │             option 1               │
///  │░░░░░░░░░░░░░option░2░░░░░░░░░░░░░░░│
///  │             option 3               │
///  └────────────────────────────────────┘
/// ```
pub fn OptionsArea(comptime Item: type) type {
    return struct {
        const Self = @This();

        /// Returns true to close the parent window.
        pub const OnReleaseButton = *const fn (
            owner: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!bool;

        /// Returns true to close the parent window.
        pub const OnHoldButton = *const fn (
            owner: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!bool;

        pub const Option = struct {
            item: Item,
            /// A buffer for a label content
            label_buffer: [LINE_BUFFER_SIZE]u8,
            /// An actual length of a label content
            label_len: usize,
            onReleaseButtonFn: OnReleaseButton,
            onHoldButtonFn: ?OnHoldButton,

            /// Returns a slice with a text of the label (no additional spaces).
            pub fn label(self: *const @This()) []const u8 {
                return self.label_buffer[0..self.label_len];
            }
        };

        /// The context is always passed to button handlers
        context: *anyopaque,
        options: std.ArrayListUnmanaged(Option),
        text_align: g.TextAlign,
        /// The absolute index of the selected line (includes the lines out of scroll)
        selected_line: usize = 0,

        pub fn centered(owner: *anyopaque) Self {
            return .init(owner, .center);
        }

        pub fn init(context: *anyopaque, text_align: g.TextAlign) Self {
            return .{ .context = context, .text_align = text_align, .options = .empty };
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

        pub fn selectedLine(self: Self) ?usize {
            return self.selected_line;
        }

        /// Returns a button to choose the selected option.
        /// Returned button is used to draw its label.
        pub fn button(self: Self) ?struct { []const u8, bool } {
            if (self.options.items.len > 0) {
                const option = self.options.items[self.selected_line];
                return .{ "Choose", option.onHoldButtonFn != null };
            } else {
                return null;
            }
        }

        /// Adds a labeled option. The `label` is copied to an inner buffer.
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

        pub fn addEmptyOption(
            self: *Self,
            alloc: std.mem.Allocator,
            item: Item,
        ) !*Option {
            const line = try self.options.addOne(alloc);
            line.* = .{
                .item = item,
                .label_len = 0,
                .label_buffer = @splat(' '),
                .onReleaseButtonFn = doNothing,
                .onHoldButtonFn = null,
            };
            return line;
        }

        fn doNothing(_: *anyopaque, _: usize, _: Item) anyerror!bool {
            return false;
        }

        pub fn selectLine(self: *Self, idx: usize) !void {
            std.debug.assert(idx < self.options.items.len);
            self.selected_line = idx;
        }

        pub fn selectPreviousLine(self: *Self) void {
            if (self.selected_line > 0)
                self.selected_line -= 1;
        }

        pub fn selectNextLine(self: *Self) void {
            if (self.selected_line < self.options.items.len - 1)
                self.selected_line += 1;
        }

        pub fn selectedOption(self: Self) *Option {
            return &self.options.items[self.selected_line];
        }

        pub fn selectedItem(self: Self) Item {
            return self.options.items[self.selected_line].item;
        }

        /// Returns true to close the parent window.
        pub fn handleButton(self: *Self, btn: g.Button) !bool {
            switch (btn.game_button) {
                .up => self.selectPreviousLine(),
                .down => self.selectNextLine(),
                .a => if (self.options.items.len > 0) {
                    const option = self.options.items[self.selected_line];
                    if (btn.state == .hold and option.onHoldButtonFn != null) {
                        return try option.onHoldButtonFn.?(self.context, self.selected_line, option.item);
                    } else {
                        return try option.onReleaseButtonFn(self.context, self.selected_line, option.item);
                    }
                },
                else => {},
            }
            return false;
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
            var point = region.top_left;
            for (0..region.rows) |r| {
                const line_idx = scrolled + r;
                if (line_idx < self.options.items.len) {
                    const label = self.options.items[line_idx].label();
                    const mode: g.DrawingMode = if (self.selected_line == line_idx) .inverted else .normal;
                    try render.drawTextWithAlign(region.cols, label, point, mode, self.text_align);
                } else {
                    try render.drawHorizontalLine(' ', point, region.cols);
                }
                point.move(.down);
            }
        }
    };
}
