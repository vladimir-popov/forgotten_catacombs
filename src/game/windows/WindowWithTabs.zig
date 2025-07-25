//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║       Tab 1     ║       Tab 2       ║║
//! ║╔╝                 ╚═══════════════════║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║║                                      ║║
//! ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║
//! ║                     Close       Choose ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const w = g.windows;

const Self = @This();

pub const Tab = struct {
    title: []const u8,
    window: w.OptionsWindow(g.Entity),

    fn deinit(self: *Tab, alloc: std.mem.Allocator) void {
        self.window.deinit(alloc);
        self.title = undefined;
    }
};

const MAX_TABS = 2;
const BORDERED_REGION = w.TextArea.Options.full_screen.region;
pub const TAB_CONTENT_OPTIONS = blk: {
    var prototype = w.TextArea.Options.full_screen;
    // reserve one line for the title separator and one line for upper border
    prototype.region.top_left.row += 2;
    prototype.region.rows -= 3;
    // reserve two columns for border
    prototype.region.top_left.col += 1;
    prototype.region.cols -= 2;
    break :blk prototype;
};

owner: *anyopaque,
tabs: [MAX_TABS]Tab = undefined,
tabs_count: u8 = 0,
active_tab_idx: usize = 0,

pub fn init(owner: *anyopaque) Self {
    return .{ .owner = owner };
}

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (0..self.tabs_count) |idx| {
        self.tabs[idx].deinit(alloc);
    }
}

pub fn addTab(self: *Self, title: []const u8, left_button_label: []const u8, right_button_label: []const u8) void {
    std.debug.assert(self.tabs_count < MAX_TABS);
    self.tabs[self.tabs_count] = .{
        .title = title,
        .window = w.OptionsWindow(g.Entity).init(
            self.owner,
            TAB_CONTENT_OPTIONS,
            left_button_label,
            right_button_label,
        ),
    };
    self.tabs_count += 1;
}

pub fn removeLastTab(self: *Self, alloc: std.mem.Allocator) void {
    if (self.tabs_count > 0) {
        self.tabs_count -= 1;
        if (self.active_tab_idx == self.tabs_count)
            self.active_tab_idx -= 1;
        self.tabs[self.tabs_count].deinit(alloc);
    }
}

// true for close
pub fn handleButton(self: *Self, btn: g.Button) !bool {
    switch (btn.game_button) {
        .left => if (self.active_tab_idx > 0) {
            self.active_tab_idx -= 1;
        },
        .right => if (self.active_tab_idx < self.tabs_count - 1) {
            self.active_tab_idx += 1;
        },
        else => switch (try self.tabs[self.active_tab_idx].window.handleButton(btn)) {
            .close_btn => return true,
            else => {},
        },
    }
    return false;
}

pub fn draw(self: Self, render: g.Render) !void {
    try self.tabs[self.active_tab_idx].window.draw(render);
    const tab_title_width: u8 = @intCast((BORDERED_REGION.cols - 2) / self.tabs_count);
    try render.drawDoubledBorder(BORDERED_REGION);
    try render.drawHorizontalLine(
        '═',
        BORDERED_REGION.top_left.movedToNTimes(.down, 2).movedTo(.right),
        BORDERED_REGION.cols - 2,
    );
    for (self.tabs[0..self.tabs_count], 0..) |tab, idx| {
        const cursor = BORDERED_REGION.top_left
            .movedTo(.down)
            .movedToNTimes(.right, @intCast(1 + idx * tab_title_width));
        try render.drawTextWithAlign(
            tab_title_width,
            tab.title,
            cursor,
            .normal,
            .center,
        );
    }
    // Draw a border around the active tab
    const cursor = BORDERED_REGION.top_left
        .movedTo(.down)
        .movedToNTimes(.right, @intCast(self.active_tab_idx * tab_title_width));
    const cursor_above = cursor.movedTo(.up);
    const underline_cursor = cursor.movedTo(.down);
    try render.drawSymbol('╔', cursor_above, .normal);
    try render.drawSymbol('╗', cursor_above.movedToNTimes(.right, tab_title_width + 1), .normal);

    try render.drawSymbol('║', cursor, .normal);
    try render.drawSymbol('║', cursor.movedToNTimes(.right, tab_title_width + 1), .normal);

    try render.drawHorizontalLine(' ', underline_cursor, tab_title_width + 1);
    try render.drawSymbol(
        if (self.active_tab_idx > 0) '╝' else '║',
        underline_cursor,
        .normal,
    );
    try render.drawSymbol(
        if (self.active_tab_idx < self.tabs_count - 1) '╚' else '║',
        underline_cursor.movedToNTimes(.right, tab_title_width + 1),
        .normal,
    );
}
