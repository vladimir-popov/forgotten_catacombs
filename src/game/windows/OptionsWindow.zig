//! This is a window with a list of options.
//! You may add options with items and right button handlers. An appropriate handler will be invoked
//! on `handleButton` method invocation. The index of the current line and appropriate item
//! will be passed to the handler, and one of the possible outcome will be returned from the
//! `handleButton`.
//! ╔════════════════════════════════════════╗
//! ║                                        ║
//! ║                                        ║
//! ║ ┌────────────────────────────────────┐ ║
//! ║ │             option 1               │ ║
//! ║ │░░░░░░░░░░░░░option░2░░░░░░░░░░░░░░░│ ║
//! ║ │             option 3               │ ║
//! ║ └────────────────────────────────────┘ ║
//! ║                                        ║
//! ║                                        ║
//! ║                                        ║
//! ║════════════════════════════════════════║
//! ║                          Close  Choose ║
//! ╚════════════════════════════════════════╝
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

pub fn OptionWindow(comptime Item: type) type {
    return struct {
        pub const HandleResult = enum {
            /// A button to close the window was pressed.
            close_btn,
            /// Up or down button was pressed.
            select_btn,
            /// Unhandled button (left or right) was pressed.
            ignored,
            /// A button to choose the current option was pressed.
            choose_btn,
        };

        const Self = @This();

        pub const OnReleaseButton = *const fn (
            handler: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!void;

        pub const OnHoldButton = *const fn (
            handler: *anyopaque,
            line_idx: usize,
            item: Item,
        ) anyerror!void;

        pub const Option = struct { item: Item, onReleaseButtonFn: OnReleaseButton, onHoldButtonFn: ?OnHoldButton };

        text_area: w.TextArea,
        /// The absolute index of the selected line (includes the lines out of scroll)
        selected_line: ?usize,
        handler: *anyopaque,
        options: std.ArrayListUnmanaged(Option),
        left_button_label: []const u8,
        right_button_label: []const u8,
        // if the window is above scene, the buffer should be drawn to hide the window,
        // or fill the region with spaces otherwise
        above_scene: bool = true,

        pub fn init(
            handler: *anyopaque,
            draw_opts: w.DrawOptions,
            left_button_label: []const u8,
            right_button_label: []const u8,
        ) Self {
            return .{
                .handler = handler,
                .text_area = w.TextArea.init(draw_opts),
                .options = .empty,
                .selected_line = null,
                .left_button_label = left_button_label,
                .right_button_label = right_button_label,
            };
        }

        pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
            self.text_area.deinit(alloc);
            self.options.deinit(alloc);
        }

        pub fn clearRetainingCapacity(self: *Self) void {
            self.text_area.lines.clearRetainingCapacity();
            self.text_area.highlighted_lines = .{ .mask = 0 };
            self.options.clearRetainingCapacity();
            self.selected_line = null;
        }

        pub fn addOption(
            self: *Self,
            alloc: std.mem.Allocator,
            label: []const u8,
            item: Item,
            onReleaseButtonFn: OnReleaseButton,
            onHoldButtonFn: ?OnHoldButton,
        ) !void {
            try self.text_area.addLine(alloc, label, false);
            try self.options.append(
                alloc,
                .{ .item = item, .onReleaseButtonFn = onReleaseButtonFn, .onHoldButtonFn = onHoldButtonFn },
            );
            if (self.selected_line == null) {
                self.selected_line = 0;
                self.text_area.highlightLine(0);
            }
        }

        pub fn selectLine(self: *Self, idx: usize) !void {
            std.debug.assert(idx < self.options.items.len);
            if (self.selected_line) |line| {
                self.text_area.unhighlightLine(line);
            }
            self.selected_line = idx;
            self.text_area.highlightLine(idx);
        }

        pub fn selectPreviousLine(self: *Self) void {
            if (self.selected_line) |selected_line| {
                self.text_area.unhighlightLine(selected_line);
                if (selected_line > 0)
                    self.selected_line = selected_line - 1
                else
                    self.selected_line = self.text_area.lines.items.len - 1;
                self.text_area.highlightLine(self.selected_line.?);
            }
        }

        pub fn selectNextLine(self: *Self) void {
            if (self.selected_line) |selected_line| {
                self.text_area.unhighlightLine(selected_line);
                if (selected_line < self.text_area.lines.items.len - 1)
                    self.selected_line = selected_line + 1
                else
                    self.selected_line = 0;
                self.text_area.highlightLine(self.selected_line.?);
            }
        }

        /// true means that the button is recognized or handled
        pub fn handleButton(self: *Self, btn: g.Button) !HandleResult {
            switch (btn.game_button) {
                .up => self.selectPreviousLine(),
                .down => self.selectNextLine(),
                .a => if (self.selected_line) |idx| {
                    const option = self.options.items[idx];
                    if (btn.state == .hold and option.onHoldButtonFn != null) {
                        try option.onHoldButtonFn.?(self.handler, idx, option.item);
                    } else {
                        try option.onReleaseButtonFn(self.handler, idx, option.item);
                    }
                    return .choose_btn;
                },
                .b => return .close_btn,
                else => return .ignored,
            }
            return .select_btn;
        }

        pub fn draw(self: *const Self, render: g.Render) !void {
            log.debug(
                "Draw options {d}; selected line {any};",
                .{ self.options.items.len, self.selected_line },
            );
            try self.text_area.draw(render);
            try render.drawLeftButton(self.left_button_label);
            if (self.selected_line) |idx| {
                const option = self.options.items[idx];
                try render.drawRightButton(self.right_button_label, option.onHoldButtonFn != null);
            } else {
                try render.hideRightButton();
            }
        }

        pub fn hide(self: *Self, render: g.Render) !void {
            if (self.above_scene)
                try render.redrawRegionFromSceneBuffer(self.text_area.region())
            else
                try render.fillRegion(' ', .normal, self.text_area.region());
        }

        pub fn close(self: *Self, alloc: std.mem.Allocator, render: g.Render) !void {
            log.debug("Close options window", .{});
            try self.hide(render);
            self.deinit(alloc);
        }
    };
}
