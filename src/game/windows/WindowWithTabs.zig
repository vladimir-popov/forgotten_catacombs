//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║       Tab 1     ║       Tab 2       ║║
//! ║╔╝                 ╚═══════════════════║║
//! ║║┌────────────────────────────────────┐║║
//! ║║│                                    │║║
//! ║║│                                    │║║
//! ║║│         OPTIONS_AREA_REGION        │║║
//! ║║│                                    │║║
//! ║║│                                    │║║
//! ║║└────────────────────────────────────┘║║
//! ║╚══════════════════════════════════════╝║
//! ║════════════════════════════════════════║
//! ║                     Close       Choose ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

pub const MAX_TABS = 3;
pub const BORDERED_REGION = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS); // -2 rows for infoBar
pub const CONTENT_AREA_REGION: p.Region = .{
    .top_left = .{
        // 1 + reserved lines for the title, separator and one line for upper border
        .row = 4,
        // 1 + reserved line for the border
        .col = 2,
    },
    // -2 rows for infoBar -4 for title, separator and up and down borders
    .rows = g.DISPLAY_ROWS - 2 - 4,
    .cols = g.DISPLAY_COLS - 2,
};

pub const Tab = struct {
    title: []const u8,
    scrollable_area: w.ScrollableArea(w.OptionsArea(g.Entity)),

    fn deinit(self: *Tab, alloc: std.mem.Allocator) void {
        self.scrollable_area.deinit(alloc);
        self.title = undefined;
    }
};

const Self = @This();

tabs: [MAX_TABS]Tab = undefined,
tabs_count: u8 = 0,
active_tab_idx: usize = 0,

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    for (0..self.tabs_count) |idx| {
        self.tabs[idx].deinit(alloc);
    }
}

/// Adds one more tab to this window.
///   - `context` is a pointer that will be passed to every option handler on this tab.
pub fn addTab(self: *Self, title: []const u8, context: *anyopaque) void {
    std.debug.assert(self.tabs_count < MAX_TABS);
    self.tabs[self.tabs_count] = .{
        .title = title,
        .scrollable_area = .init(w.OptionsArea(g.Entity).init(context, .left), CONTENT_AREA_REGION),
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

pub fn activeTab(self: *Self) *Tab {
    return &self.tabs[self.active_tab_idx];
}

/// true means the window should be closed
pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    const tab = &self.tabs[self.active_tab_idx];
    if (try tab.scrollable_area.handleButton(btn) == .close_window)
        return .close_window;

    switch (btn.game_button) {
        .a => return if (tab.scrollable_area.button() == null) .close_window else .keep_open,
        .b => return .close_window,
        .left => if (self.active_tab_idx > 0) {
            self.active_tab_idx -= 1;
        },
        .right => if (self.active_tab_idx < self.tabs_count - 1) {
            self.active_tab_idx += 1;
        },
        else => {},
    }
    return .keep_open;
}

pub fn draw(self: Self, render: g.Render) !void {
    log.debug(
        "Drawing window with tabs in {any}. Tab {d}/{d}",
        .{ BORDERED_REGION, self.active_tab_idx, self.tabs_count },
    );
    // Draw the tab titles
    const tab_title_width: u8 = (BORDERED_REGION.cols - 2) / self.tabs_count;
    try render.drawDoubledBorder(BORDERED_REGION, g.Render.default_filler);
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
    if (self.tabs_count > 1) {
        try render.drawHorizontalLine(
            '═',
            BORDERED_REGION.top_left.movedToNTimes(.down, 2).movedTo(.right),
            BORDERED_REGION.cols - 2,
        );
        // Draw the border around the left active tab
        if (self.active_tab_idx == 0) {
            var cursor = BORDERED_REGION.top_left
                .movedToNTimes(.down, 2);
            try render.drawHorizontalLine(' ', cursor.movedTo(.right), tab_title_width - 1);
            cursor.moveNTimes(.right, tab_title_width);
            try render.drawSymbol('╚', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.up);
            try render.drawSymbol('╗', cursor, .normal);
        } // Draw the border around the right active tab
        else if (self.active_tab_idx == self.tabs_count - 1) {
            var cursor = BORDERED_REGION.topRight()
                .movedToNTimes(.left, tab_title_width + 1);
            try render.drawSymbol('╔', cursor, .normal);
            cursor.move(.down);
            try render.drawSymbol('║', cursor, .normal);
            cursor.move(.down);
            try render.drawHorizontalLine(' ', cursor, tab_title_width + 1);
            try render.drawSymbol('╝', cursor, .normal);
        } // Draw the border around middle tabs
        else {
            var cursor = BORDERED_REGION.top_left
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

    // Draw the content
    try self.tabs[self.active_tab_idx].scrollable_area.draw(render);

    // Draw the buttons
    if (self.tabs[self.active_tab_idx].scrollable_area.button()) |button| {
        try render.drawRightButton(button[0], button[1]);
        try render.drawLeftButton("Close", false);
    } else {
        try render.drawRightButton("Close", false);
        try render.hideLeftButton();
    }
}
