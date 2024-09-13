const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");
const utf8 = @import("utf8.zig");

const log = std.log.scoped(.tty_menu);

const Menu = @This();

const Item = struct {
    title: []const u8,
    game_object: *anyopaque,
    callback: g.Runtime.MenuItemCallback,
};

const LEFT_PAD = g.DISPLAY_COLS / 2;
const TITLE_LENGTH = g.DISPLAY_COLS - LEFT_PAD;
const MAX_ITEMS_COUNT = 3;

// Used to manage the buffer
arena: std.heap.ArenaAllocator,
// The buffer with the game on background and the rendered menu
buffer: utf8.Buffer = undefined,
is_shown: bool = false,
items: [MAX_ITEMS_COUNT]Item = undefined,
items_count: u4 = 0,
selected_item: u4 = 0,

pub fn init(alloc: std.mem.Allocator) Menu {
    return .{ .arena = std.heap.ArenaAllocator.init(alloc) };
}

pub fn deinit(self: *Menu) void {
    self.is_shown = false;
    _ = self.arena.reset(.free_all);
}

pub fn handleKeyboardButton(self: *Menu, btn: g.Button) !void {
    try self.drawMenuItem(self.selected_item, true);

    switch (btn.game_button) {
        .a => if (self.items_count > 0) {
            const game_object = self.items[self.selected_item].game_object;
            try self.close();
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
}

pub fn show(self: *Menu, rendered_game: utf8.Buffer) !void {
    log.debug("Show menu with {d} items", .{self.items_count});
    self.is_shown = true;
    self.buffer = try rendered_game.copy(self.arena.allocator());
    // draw border
    try self.buffer.set('╔', 0, LEFT_PAD);
    for (1..g.DISPLAY_ROWS + 1) |r| {
        try self.buffer.mergeLine("║" ++ " " ** TITLE_LENGTH, r, g.DISPLAY_COLS / 2);
    }
    try self.buffer.set('╚', g.DISPLAY_ROWS + 1, LEFT_PAD);
    // draw items
    for (0..self.items_count) |i| {
        try self.drawMenuItem(@intCast(i), false);
    }
    try self.drawMenuItem(self.selected_item, true);
}

fn drawMenuItem(self: *Menu, item_idx: u4, comptime is_selected: bool) !void {
    if (item_idx >= self.items_count) return;

    const fmt = if (is_selected)
        std.fmt.comptimePrint(tty.Text.inverted("{{s:^{d}}}"), .{TITLE_LENGTH})
    else
        std.fmt.comptimePrint("{{s:^{d}}}", .{TITLE_LENGTH});
    const buf_length = if (is_selected) TITLE_LENGTH + 7 else TITLE_LENGTH;
    var buf: [buf_length]u8 = undefined;
    const item = self.items[item_idx];
    const len = @min(TITLE_LENGTH, item.title.len);
    _ = try std.fmt.bufPrint(&buf, fmt, .{item.title[0..len]});
    try self.buffer.mergeLine(&buf, item_idx * 3 + 2, LEFT_PAD + 1);
}

pub fn close(self: *Menu) !void {
    log.debug("Close menu with {d} items and {d} selected", .{ self.items_count, self.selected_item });
    self.is_shown = false;
    _ = self.arena.reset(.retain_capacity);
}

pub fn addMenuItem(
    self: *Menu,
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

pub inline fn removeAllItems(self: *Menu) void {
    log.debug("Remove all {d} items", .{self.items_count});
    self.items_count = 0;
    self.selected_item = 0;
}
