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

        pub const ButtonHandler = struct {
            handle_release_button: *const fn (
                context: *anyopaque,
                selected_line: usize,
                item: Item,
            ) anyerror!w.HandleButtonResult,

            handle_hold_button: ?*const fn (
                context: *anyopaque,
                selected_line: usize,
                item: Item,
            ) anyerror!w.HandleButtonResult = null,

            const do_nothing: ButtonHandler = .{ .handle_release_button = doNothing };

            fn doNothing(_: *anyopaque, _: usize, _: Item) anyerror!w.HandleButtonResult {
                return .keep_open;
            }
        };

        pub const Option = struct {
            /// A buffer for a label content
            label_buffer: [LINE_BUFFER_SIZE]u8,
            /// An actual length of a label content
            label_len: usize,
            item: Item,
            button_handler: ButtonHandler,

            /// Returns a slice with a text of the label (no additional spaces).
            pub fn label(self: *const @This()) []const u8 {
                return self.label_buffer[0..self.label_len];
            }

            pub fn onRightButtonPressed(
                self: Option,
                state: g.Button.State,
                context: *anyopaque,
                selected_line: usize,
            ) !w.HandleButtonResult {
                switch (state) {
                    .released => return try self.button_handler.handle_release_button(context, selected_line, self.item),
                    .hold => return if (self.button_handler.handle_hold_button) |handle|
                        handle(context, selected_line, self.item)
                    else
                        .keep_open,
                }
            }
        };

        alloc: std.mem.Allocator,
        /// The context is always passed to button handlers
        context: *anyopaque,
        options: std.ArrayList(Option),
        text_align: g.TextAlign,
        /// The absolute index of the selected line (includes the lines out of scroll)
        selected_line: usize = 0,

        pub fn initEmpty(alloc: std.mem.Allocator, context: *anyopaque, text_align: g.TextAlign) Self {
            return .{ .alloc = alloc, .context = context, .text_align = text_align, .options = .empty };
        }

        pub fn deinit(self: *Self) void {
            self.options.deinit(self.alloc);
        }

        pub fn area(self: *Self) w.Area {
            return .{ .underlying = self, .vtable = w.Area.vtableFor(Self) };
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.options.clearRetainingCapacity();
            self.selected_line = 0;
        }

        pub fn totalLines(self: *const Self) usize {
            return self.options.items.len;
        }

        pub fn leftButton(self: *const Self) ?w.Button {
            return if (self.options.items.len > 0) .close else null;
        }

        pub fn rightButton(self: *const Self) ?w.Button {
            return if (self.options.items.len > 0)
                if (self.options.items[self.selected_line].button_handler.handle_hold_button) |_|
                    .choose_with_alternatives
                else
                    .choose
            else
                .close;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            switch (btn.game_button) {
                .up => self.selectPreviousLine(),
                .down => self.selectNextLine(),
                .a => if (self.options.items.len > 0) {
                    const option = self.options.items[self.selected_line];
                    if (btn.state == .released) {
                        return try option.onRightButtonPressed(btn.state, self.context, self.selected_line);
                    }
                } else {
                    return .close_window;
                },
                .b => if (self.options.items.len > 0) return .close_window,
                else => {},
            }
            return .keep_open;
        }

        /// Adds a labeled option. The `label` is copied to an inner buffer.
        pub fn addOption(
            self: *Self,
            label: []const u8,
            item: Item,
            handler: ButtonHandler,
        ) !void {
            std.debug.assert(label.len < LINE_BUFFER_SIZE);

            const line = try self.options.addOne(self.alloc);
            line.* = .{
                .item = item,
                .label_len = label.len,
                .label_buffer = undefined,
                .button_handler = handler,
            };
            @memmove(line.label_buffer[0..line.label_len], label);
        }

        pub fn addOptionFmt(
            self: *Self,
            comptime fmt: []const u8,
            args: anytype,
            item: Item,
            handler: ButtonHandler,
        ) !void {
            const line = try self.options.addOne(self.alloc);
            line.* = .{
                .item = item,
                .label_len = 0,
                .label_buffer = undefined,
                .button_handler = handler,
            };
            line.label_len = (try std.fmt.bufPrint(&line.label_buffer, fmt, args)).len;
        }

        pub fn addEmptyOption(
            self: *Self,
            item: Item,
        ) !*Option {
            const line = try self.options.addOne(self.alloc);
            line.* = .{
                .item = item,
                .label_len = 0,
                .label_buffer = @splat(' '),
                .button_handler = .do_nothing,
            };
            return line;
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

        pub fn selectedLine(self: Self) ?usize {
            return if (self.options.items.len > 0)
                self.selected_line
            else
                null;
        }

        pub fn selectedOption(self: *const Self) ?*Option {
            return if (self.selectedLine()) |idx|
                &self.options.items[idx]
            else
                null;
        }

        pub fn selectedItem(self: *const Self) ?Item {
            return if (self.selectedLine()) |idx|
                self.options.items[idx].item
            else
                null;
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
    };
}
