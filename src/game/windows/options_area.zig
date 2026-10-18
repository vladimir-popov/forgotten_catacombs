const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;
const AllocatorError = std.mem.Allocator.Error;

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

        /// Callbacks invoked when an option is activated or held.
        pub const ButtonHandler = struct {
            handle_release_button: *const fn (
                context: *anyopaque,
                selected_line: usize,
                item: Item,
            ) g.AllErrors!w.HandleButtonResult,

            handle_hold_button: ?*const fn (
                context: *anyopaque,
                selected_line: usize,
                item: Item,
            ) g.AllErrors!w.HandleButtonResult = null,

            /// A handler that leaves the area open without performing an action.
            pub const do_nothing: ButtonHandler = .{ .handle_release_button = doNothing };

            fn doNothing(_: *anyopaque, _: usize, _: Item) g.AllErrors!w.HandleButtonResult {
                return .keep_open;
            }
        };

        /// A labeled item and the callbacks associated with it.
        pub const Option = struct {
            /// A buffer for a label content
            label_buffer: [LINE_BUFFER_SIZE]u8,
            /// An actual length of a label content
            label_len: usize,
            item: Item,
            button_handler: ButtonHandler,

            /// Returns the label without trailing padding.
            pub fn label(self: *const @This()) []const u8 {
                return self.label_buffer[0..self.label_len];
            }
        };

        alloc: std.mem.Allocator,
        /// The context is always passed to button handlers
        context: *anyopaque,
        options: std.ArrayList(Option),
        text_align: g.TextAlign,
        /// The absolute index of the selected line (includes the lines out of scroll)
        selected_line: usize = 0,

        /// Creates an empty options area with a borrowed handler context.
        pub fn initEmpty(alloc: std.mem.Allocator, context: *anyopaque, text_align: g.TextAlign) Self {
            return .{ .alloc = alloc, .context = context, .text_align = text_align, .options = .empty };
        }

        /// Releases the option labels and backing storage.
        pub fn deinit(self: *Self) void {
            self.options.deinit(self.alloc);
        }

        /// Returns the button shown for the current selection.
        pub fn getButtons(self: *Self) w.Buttons {
            if (self.options.items.len == 0) {
                return .{};
            }

            const has_alternative = if (self.selectedOption()) |opt|
                opt.button_handler.handle_hold_button != null
            else
                false;

            return .{
                .right = .{ .label = "Choose", .has_alternative = has_alternative },
            };
        }

        /// Handles selection movement and option activation.
        pub fn handleButton(self: *Self, btn: g.Button) g.AllErrors!w.HandleButtonResult {
            switch (btn.game_button) {
                .up => self.selectPreviousLine(),
                .down => self.selectNextLine(),
                .a => if (self.options.items.len > 0) {
                    const option = self.options.items[self.selected_line];
                    const is_helt = btn.state == .hold;
                    return if (!is_helt)
                        try option.button_handler.handle_release_button(self.context, self.selected_line, option.item)
                    else if (option.button_handler.handle_hold_button) |handle_hold_button|
                        try handle_hold_button(self.context, self.selected_line, option.item)
                    else
                        .keep_open;
                },
                else => {},
            }
            return .keep_open;
        }

        /// Draws the options line by line inside the passed region. If the region has not enough
        /// rows, then the options will be scrolled. If the region has not enough columns, then
        /// the label will be cropped.
        ///
        /// - `region` - A region where this aria should be drawn. For left aligned text the first
        /// symbol will be drawn at the top left corner of the passed region.
        ///
        /// - `scrolled` - How many scrolled lines should be skipped.
        /// Draws the visible options and highlights the selected line.
        pub fn drawContent(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) (g.Runtime.Error || g.Utf8Error)!void {
            // Clear the region
            try render.fillRegion(g.Render.default_filler, .normal, region);
            // Draw the options
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

        /// Removes all options while retaining allocated capacity.
        pub fn clearRetainingCapacity(self: *Self) void {
            self.options.clearRetainingCapacity();
            self.selected_line = 0;
        }

        /// Returns the number of options.
        pub fn totalLines(self: *const Self) usize {
            return self.options.items.len;
        }

        /// Adds a labeled option. The `label` is copied to an inner buffer.
        pub fn addOption(
            self: *Self,
            label: []const u8,
            item: Item,
            handler: ButtonHandler,
        ) AllocatorError!*Option {
            std.debug.assert(label.len < LINE_BUFFER_SIZE);

            const option = try self.options.addOne(self.alloc);
            option.* = .{
                .item = item,
                .label_len = label.len,
                .label_buffer = undefined,
                .button_handler = handler,
            };
            @memmove(option.label_buffer[0..option.label_len], label);
            return option;
        }

        /// Appends an option with a formatted label.
        pub fn addOptionFmt(
            self: *Self,
            comptime fmt: []const u8,
            args: anytype,
            item: Item,
            handler: ButtonHandler,
        ) (AllocatorError || std.fmt.BufPrintError)!*Option {
            const option = try self.options.addOne(self.alloc);
            option.* = .{
                .item = item,
                .label_len = 0,
                .label_buffer = undefined,
                .button_handler = handler,
            };
            option.label_len = (try std.fmt.bufPrint(&option.label_buffer, fmt, args)).len;
            return option;
        }

        /// Appends an option with a blank label and no-op handler.
        pub fn addEmptyOption(
            self: *Self,
            item: Item,
        ) AllocatorError!*Option {
            const option = try self.options.addOne(self.alloc);
            option.* = .{
                .item = item,
                .label_len = 0,
                .label_buffer = @splat(' '),
                .button_handler = .do_nothing,
            };
            return option;
        }

        /// Selects an option by its zero-based index.
        pub fn selectLine(self: *Self, idx: usize) void {
            std.debug.assert(idx < self.options.items.len);
            self.selected_line = idx;
        }

        /// Moves the selection one line up when possible.
        pub fn selectPreviousLine(self: *Self) void {
            if (self.selected_line > 0)
                self.selected_line -= 1;
        }

        /// Moves the selection one line down when possible.
        pub fn selectNextLine(self: *Self) void {
            if (self.selected_line + 1 < self.options.items.len)
                self.selected_line += 1;
        }

        /// Returns the selected option index, or null when the area is empty.
        pub fn selectedLine(self: Self) ?usize {
            return if (self.options.items.len > 0)
                self.selected_line
            else
                null;
        }

        /// Returns the selected option, if one exists.
        pub fn selectedOption(self: *const Self) ?*Option {
            return if (self.selectedLine()) |idx|
                &self.options.items[idx]
            else
                null;
        }

        /// Returns the item stored in the selected option.
        pub fn selectedItem(self: *const Self) ?Item {
            return if (self.selectedLine()) |idx|
                self.options.items[idx].item
            else
                null;
        }
    };
}
