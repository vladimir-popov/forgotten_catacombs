const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");

const log = std.log.scoped(.tty_menu);

const DisplayBuffer = @import("DisplayBuffer.zig").DisplayBuffer;

const Item = struct {
    title: []const u8,
    game_object: *anyopaque,
    callback: g.Runtime.MenuItemCallback,
};

pub fn Menu(comptime ROWS: u8, comptime COLS: u8) type {
    return struct {
        const TITLE_LENGTH = COLS - 2;
        const MAX_ITEMS_COUNT = 3;

        const Self = @This();

        buffer: DisplayBuffer(ROWS, COLS),
        is_shown: bool = false,
        items: [MAX_ITEMS_COUNT]Item = undefined,
        items_count: u4 = 0,
        selected_item: u4 = 0,

        pub fn init(alloc: std.mem.Allocator) !Self {
            return .{ .buffer = try DisplayBuffer(ROWS, COLS).init(alloc) };
        }

        pub fn deinit(self: Self) void {
            self.buffer.deinit();
        }

        pub fn handleKeyboardButton(self: *Self, btn: g.Button) !void {
            switch (btn.game_button) {
                .a => if (self.items_count > 0) {
                    const game_object = self.items[self.selected_item].game_object;
                    self.close();
                    self.items[self.selected_item].callback(game_object);
                },
                .up => if (self.selected_item > 0) {
                    self.selected_item -= 1;
                },
                .down => if (self.selected_item < MAX_ITEMS_COUNT - 2) {
                    self.selected_item += 1;
                },
                else => {},
            }
            try self.drawMenuItems();
        }

        pub fn show(self: *Self) !void {
            log.debug("Show menu with {d} items", .{self.items_count});
            self.is_shown = true;
            self.buffer.cleanAndWrap();
            try self.drawMenuItems();
        }

        inline fn drawMenuItems(self: Self) !void {
            for (0..self.items_count) |i| {
                try self.drawMenuItem(@intCast(i), i == self.selected_item);
            }
        }

        fn drawMenuItem(self: Self, item_idx: u4, is_selected: bool) !void {
            if (item_idx >= self.items_count) return;

            const mode: g.DrawingMode = if (is_selected) .inverted else .normal;
            const item = self.items[item_idx];
            var buf: [TITLE_LENGTH]u8 = undefined;
            var fbs = std.io.fixedBufferStream(&buf);
            try std.fmt.formatBuf(item.title, .{ .alignment = .center, .width = TITLE_LENGTH }, fbs.writer().any());
            self.buffer.setAsciiText(fbs.getWritten(), item_idx * 3 + 2, 1, mode);
        }

        pub fn close(self: *Self) void {
            log.debug("Close menu with {d} items and {d} selected", .{ self.items_count, self.selected_item });
            self.is_shown = false;
        }

        pub fn addMenuItem(
            self: *Self,
            title: []const u8,
            game_object: *anyopaque,
            callback: g.Runtime.MenuItemCallback,
        ) ?*anyopaque {
            if (self.items_count == self.items.len) return null;

            log.debug("Add menu item {s}", .{title});

            const i = self.items_count;
            self.items[i] = .{
                .title = title,
                .game_object = game_object,
                .callback = callback,
            };
            self.items_count += 1;
            return &self.items[i];
        }

        pub inline fn removeAllItems(self: *Self) void {
            log.debug("Remove all {d} items", .{self.items_count});
            self.items_count = 0;
            self.selected_item = 0;
        }
    };
}
