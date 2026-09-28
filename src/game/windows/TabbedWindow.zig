//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║---------------
//! ║ ║       Tab 1     ║       Tab 2       ║║             |
//! ║╔╝                 ╚═══════════════════║║---          |
//! ║║                                      ║║ |
//! ║║                                      ║║          Whole window
//! ║║                                      ║║ Tab      region
//! ║║          OPTIONS_AREA_REGION         ║║ region
//! ║║                                      ║║             |
//! ║║                                      ║║ |           |
//! ║║                                      ║║ |           |
//! ║╚══════════════════════════════════════╝║---------------
//! ║════════════════════════════════════════║
//! ║                     Close       Choose ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const WHOLE_WINDOW_REGION = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS); // -2 rows for infoBar
const MAX_TABS = 3;

pub const Tab = struct {
    /// The region for a tab. It includes a space for the window's border, but that border is not
    /// drawn.
    pub const CONTENT_REGION: p.Region = .{
        .top_left = .{
            // reserved lines for the title, separator and one line for upper border
            .row = 3,
            // reserved line for the border
            .col = 1,
        },
        // -2 rows for infoBar, -2 for title
        .rows = g.DISPLAY_ROWS - 2 - 2,
        .cols = g.DISPLAY_COLS,
    };
    title: []const u8,
    panel: w.Panel,
};

const Self = @This();

tabs: [MAX_TABS]Tab = undefined,
tabs_len: usize = 0,
active_tab_idx: usize = 0,
is_redrawing_required: bool = true,

pub fn deinit(self: *Self) void {
    for (0..self.tabs_len) |idx| {
        self.tabs[idx].panel.deinit();
    }
    self.tabs_len = 0;
    self.tabs = undefined;
}

/// Adds one more tab with options to this window.
pub fn addOptionsTab(
    self: *Self,
    alloc: std.mem.Allocator,
    comptime Item: type,
    comptime title: []const u8,
) !*w.OptionsArea(Item) {
    std.debug.assert(self.tabs_len < MAX_TABS);
    self.tabs_len += 1;
    const tab = &self.tabs[self.tabs_len - 1];
    tab.title = title;
    return tab.panel.initWithOptions(alloc, Item, self, .left);
}

pub fn removeLastTab(self: *Self) void {
    if (self.tabs_len == 0) return;
    self.tabs[self.tabs_len - 1].panel.deinit();
    self.tabs[self.tabs_len - 1] = undefined;
    self.tabs_len -= 1;
    if (self.active_tab_idx == self.tabs_len)
        self.active_tab_idx -|= 1;
}

pub fn activeTab(self: *Self) *Tab {
    return &self.tabs[self.active_tab_idx];
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    self.is_redrawing_required = true;
    const tab = self.activeTab();
    if (try tab.panel.handleButton(btn) == .close_window)
        return .close_window;

    switch (btn.game_button) {
        .left => if (self.active_tab_idx > 0) {
            self.active_tab_idx -= 1;
        },
        .right => if (self.active_tab_idx < self.tabs_len - 1) {
            self.active_tab_idx += 1;
        },
        else => {},
    }
    return .keep_open;
}

pub fn draw(self: *Self, render: g.Render) !void {
    // Draw the tab titles
    const tab_title_width: usize = (WHOLE_WINDOW_REGION.cols - 2) / self.tabs_len;
    try render.drawDoubledBorder(WHOLE_WINDOW_REGION, g.Render.default_filler);
    for (0..self.tabs_len) |idx| {
        const cursor = WHOLE_WINDOW_REGION.top_left
            .movedTo(.down)
            .movedToNTimes(.right, @intCast(1 + idx * tab_title_width));
        try render.drawTextWithAlign(
            tab_title_width,
            self.tabs[idx].title,
            cursor,
            .normal,
            .center,
        );
    }
    if (self.tabs_len > 1) {
        try render.drawHorizontalLine(
            '═',
            WHOLE_WINDOW_REGION.top_left.movedToNTimes(.down, 2).movedTo(.right),
            WHOLE_WINDOW_REGION.cols - 2,
        );
        // Draw the border around the left active tab
        if (self.active_tab_idx == 0) {
            var cursor = WHOLE_WINDOW_REGION.top_left
                .movedToNTimes(.down, 2);
            try render.drawHorizontalLine(' ', cursor.movedTo(.right), tab_title_width - 1);
            cursor.moveNTimes(.right, tab_title_width);
            try render.drawSymbol('╚', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('╗', cursor, .normal);
        } // Draw the border around the right active tab
        else if (self.active_tab_idx == self.tabs_len - 1) {
            var cursor = WHOLE_WINDOW_REGION.topRight()
                .movedToNTimes(.left, tab_title_width + 1);
            try render.drawSymbol('╔', cursor, .normal);
            cursor.move(.down);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.down);
            try render.drawHorizontalLine(' ', cursor, tab_title_width + 1);
            try render.drawSymbol('╝', cursor, .normal);
        } // Draw the border around middle tabs
        else {
            var cursor = WHOLE_WINDOW_REGION.top_left
                .movedToNTimes(.right, @intCast(self.active_tab_idx * tab_title_width));
            try render.drawSymbol('╔', cursor, .normal);
            cursor.move(.down);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.down);
            try render.drawSymbol('╝', cursor, .normal);
            try render.drawHorizontalLine(' ', cursor.movedTo(.right), tab_title_width);
            cursor.moveNTimes(.right, tab_title_width + 1);
            try render.drawSymbol('╚', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('╗', cursor, .normal);
        }
    }

    try self.activeTab().panel.draw(render, Tab.CONTENT_REGION);
}
