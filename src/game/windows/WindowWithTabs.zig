//! ```
//! ╔════════════════════════════════════════╗
//! ║ ╔═════════════════╗═══════════════════╗║
//! ║ ║       Tab 1     ║       Tab 2       ║║
//! ║╔╝                 ╚═══════════════════║║
//! ║║┌────────────────────────────────────┐║║
//! ║║│                                    │║║
//! ║║│                                    │║║
//! ║║│         CONTENT_AREA_REGION        │║║
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

pub const MAX_TABS = 2;
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
    area: w.ScrollableAre(w.OptionsArea(g.Entity)),
    scrolled_lines: usize = 0,

    fn deinit(self: *Tab, alloc: std.mem.Allocator) void {
        self.area.deinit(alloc);
        self.title = undefined;
    }
};

const Self = @This();

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

pub fn addTab(self: *Self, title: []const u8) void {
    std.debug.assert(self.tabs_count < MAX_TABS);
    self.tabs[self.tabs_count] = .{
        .title = title,
        .area = .init(w.OptionsArea(g.Entity).init(self.owner, .left), CONTENT_AREA_REGION),
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
pub fn handleButton(self: *Self, btn: g.Button) !bool {
    const tab = &self.tabs[self.active_tab_idx];
    try tab.area.handleButton(btn);
    switch (btn.game_button) {
        .b => return true,
        .left => if (self.active_tab_idx > 0) {
            self.active_tab_idx -= 1;
        },
        .right => if (self.active_tab_idx < self.tabs_count - 1) {
            self.active_tab_idx += 1;
        },
        else => {},
    }
    return false;
}

pub fn draw(self: Self, render: g.Render) !void {
    log.debug(
        "Drawing window with tabs in {any}. Tab {d}/{d}",
        .{ BORDERED_REGION, self.active_tab_idx, self.tabs_count },
    );
    // Draw the tab titles
    const tab_title_width: u8 = @intCast((BORDERED_REGION.cols - 2) / self.tabs_count);
    try render.drawDoubledBorder(BORDERED_REGION, g.Render.default_filler);
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
    // Draw the border around the active tab
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

    // Draw the content
    try self.tabs[self.active_tab_idx].area.draw(render);

    // Draw buttons
    if (self.tabs[self.active_tab_idx].area.button()) |button| {
        try render.drawRightButton(button[0], button[1]);
        try render.drawLeftButton("Close", false);
    } else {
        try render.drawRightButton("Close", false);
        try render.hideLeftButton();
    }
}
