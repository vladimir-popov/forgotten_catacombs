const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

/// The biggest region that can be occupied by a modal window with options.
pub const MODAL_WINDOW_REGION: p.Region = p.Region.init(3, 2, g.DISPLAY_ROWS - 5, g.DISPLAY_COLS - 2);

/// The region for a tab. It includes a space for the window's border, but that border is not
/// drawn.
const TAB_REGION: p.Region = .{
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

/// A full-screen window that owns a fixed, heterogeneous set of scrollable tabs.
///
/// ```
/// ╔════════════════════════════════════════╗
/// ║ ╔═════════════════╗═══════════════════╗║---------------
/// ║ ║       Tab 1     ║       Tab 2       ║║             |
/// ║╔╝                 ╚═══════════════════║║---          |
/// ║║                                      ║║ |
/// ║║                                      ║║          Whole window
/// ║║                                      ║║ Tab      region
/// ║║          OPTIONS_AREA_REGION         ║║ region
/// ║║                                      ║║             |
/// ║║                                      ║║ |           |
/// ║║                                      ║║ |           |
/// ║╚══════════════════════════════════════╝║---------------
/// ║════════════════════════════════════════║
/// ║                     Close       Choose ║
/// ╚════════════════════════════════════════╝
/// ```
pub fn TabbedWindow(comptime Areas: anytype) type {
    return struct {
        fn Tab(comptime Area: type) type {
            return struct {
                // In all current cases titles of tabs are compile time known strings.
                title: []const u8,
                panel: w.ScrollablePanel(Area),
            };
        }

        const Tabs = g.utils.mapTypes(Areas, Tab);

        const Self = @This();

        pub const empty: Self = .{ .tabs = .empty };

        tabs: g.utils.HList(Tabs),
        active_tab_idx: usize = 0,

        pub fn deinit(self: *Self) void {
            inline for (g.utils.HList(Tabs).Fields, 0..) |field, idx| {
                if (idx < self.tabs.len) {
                    @field(self.tabs.items, field.name).panel.area.deinit();
                }
            }
            self.tabs = undefined;
        }

        pub fn getArea(self: *Self, comptime Area: type, idx: usize) ?*Area {
            const tab = self.tabs.get(Tab(Area), idx) orelse return null;
            return &tab.panel.area;
        }

        pub fn activeTab(self: *Self, comptime Area: type) ?*Area {
            return self.getArea(Area, self.active_tab_idx);
        }

        pub fn addTab(self: *Self, title: []const u8, area: anytype) !*@TypeOf(area) {
            const new_tab = self.tabs.append(Tab(@TypeOf(area)){ .title = title, .panel = .{
                .area = area,
                .region = TAB_REGION.innerRegion(1, 1, 1, 1),
            } }) orelse
                return error.TooManyTabs;
            return &new_tab.panel.area;
        }

        pub fn removeLastTab(self: *Self) void {
            if (self.tabs.removeLast() and self.active_tab_idx > 0)
                self.active_tab_idx -= 1;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            inline for (@typeInfo(Tabs).@"struct".fields, 0..) |field, idx| {
                const TabType = field.type;
                if (idx == self.active_tab_idx) {
                    const tab = self.tabs.get(TabType, idx).?;
                    if (try tab.panel.handleButton(btn) == .close_window)
                        return .close_window;
                }
            }
            switch (btn.game_button) {
                .left => if (self.active_tab_idx > 0) {
                    self.active_tab_idx -= 1;
                },
                .right => if (self.active_tab_idx < self.tabs.len - 1) {
                    self.active_tab_idx += 1;
                },
                else => {},
            }
            return .keep_open;
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            if (self.tabs.len == 0) return;

            // Draw the tab titles
            const tab_title_width: usize = (w.FULL_SCREEN_REGION.cols - 2) / self.tabs.len;
            try render.drawDoubledBorder(w.FULL_SCREEN_REGION, g.Render.default_filler);
            inline for (@typeInfo(Tabs).@"struct".fields, 0..) |field, idx| {
                if (idx < self.tabs.len) {
                    const TabType = field.type;
                    const cursor = w.FULL_SCREEN_REGION.top_left
                        .movedTo(.down)
                        .movedToNTimes(.right, @intCast(1 + idx * tab_title_width));
                    if (self.tabs.get(TabType, idx)) |tab| {
                        try render.drawTextWithAlign(
                            tab_title_width,
                            tab.title,
                            cursor,
                            .normal,
                            .center,
                        );
                    } else {
                        @panic(std.fmt.comptimePrint("Wrong type of the tab {d}", .{idx}));
                    }
                }
            }
            if (self.tabs.len > 1) {
                try render.drawHorizontalLine(
                    '═',
                    w.FULL_SCREEN_REGION.top_left.movedToNTimes(.down, 2).movedTo(.right),
                    w.FULL_SCREEN_REGION.cols - 2,
                );
                // Draw the border around the left active tab
                if (self.active_tab_idx == 0) {
                    var cursor = w.FULL_SCREEN_REGION.top_left
                        .movedToNTimes(.down, 2);
                    try render.drawHorizontalLine(' ', cursor.movedTo(.right), tab_title_width - 1);
                    cursor.moveNTimes(.right, tab_title_width);
                    try render.drawSymbol('╚', cursor, .normal);
                    cursor.move(.up);
                    try render.drawSymbol('║', cursor, .normal);
                    cursor.move(.up);
                    try render.drawSymbol('╗', cursor, .normal);
                } // Draw the border around the right active tab
                else if (self.active_tab_idx == self.tabs.len - 1) {
                    var cursor = w.FULL_SCREEN_REGION.topRight()
                        .movedToNTimes(.left, tab_title_width + 1);
                    try render.drawSymbol('╔', cursor, .normal);
                    cursor.move(.down);
                    try render.drawSymbol('║', cursor, .normal);
                    cursor.move(.down);
                    try render.drawHorizontalLine(' ', cursor, tab_title_width + 1);
                    try render.drawSymbol('╝', cursor, .normal);
                } // Draw the border around middle tabs
                else {
                    var cursor = w.FULL_SCREEN_REGION.top_left
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

            inline for (@typeInfo(Tabs).@"struct".fields, 0..) |field, idx| {
                if (idx == self.active_tab_idx) {
                    const TabType = field.type;
                    if (idx == self.active_tab_idx) {
                        const panel = &self.tabs.get(TabType, idx).?.panel;
                        try panel.draw(render);
                    }
                }
            }
        }
    };
}
