//! This is a very simple system of windows. Two key concepts exist:
//! areas and windows.
//!
//! The areas are about managing and drawing a content.
//!
//! The windows are about placing the areas somewhere on the screen.
//!
//! Both windows and areas can have a special handlers for buttons. You have
//! to manage the state of both windows and areas in their container manually.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.windows);

/// The result of handling a button. Some window can have default `Close` button (a Description
/// window as example), or have another logic to request closing itself (a window with options).
pub const HandleButtonResult = enum {
    /// Means that the window should be closed after handling a button
    close_window,
    /// Means that the window should still be open.
    keep_open,
};

pub const modal_window = @import("modal_window.zig");
pub const options_area = @import("options_area.zig");
pub const scrollable_panel = @import("scrollable_panel.zig");
pub const tabbed_window = @import("tabbed_window.zig");
pub const wizard = @import("wizard/wizard_pkg.zig");

pub const Button = @import("Button.zig");
pub const OptionsArea = options_area.OptionsArea;
pub const ModalWindow = modal_window.ModalWindow;
pub const ScrollablePanel = scrollable_panel.ScrollablePanel;
pub const TabbedWindow = tabbed_window.TabbedWindow;
pub const TextArea = @import("TextArea.zig");
pub const WindowCompositor = @import("WindowCompositor.zig");

/// A maximal region which can be occupied by a window.
/// This region includes a space for borders.
pub const FULL_SCREEN_REGION: p.Region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);

pub fn updateAreaWithItems(
    area: *OptionsArea(g.Entity),
    context: *anyopaque,
    items: g.utils.EntitiesSet,
    formatLine: *const fn (line: *TextArea.Line, context: *anyopaque, item: g.Entity) anyerror![]const u8,
    handler: OptionsArea(g.Entity).ButtonHandler,
) !void {
    area.clearRetainingCapacity();
    const selected_line = area.selected_line;
    var itr = items.iterator();
    while (itr.next()) |item_ptr| {
        var line: TextArea.Line = undefined;
        _ = try area.addOption(
            try formatLine(&line, context, item_ptr.*),
            item_ptr.*,
            handler,
        );
    }
    if (area.options.items.len > 0) {
        try area.selectLine(if (selected_line < area.options.items.len)
            selected_line
        else
            area.options.items.len - 1);
    }
}
