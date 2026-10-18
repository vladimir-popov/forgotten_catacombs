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

/// Constructors and the generic implementation of bordered modal windows.
pub const modal_window = @import("modal_window.zig");
/// A selectable list area parameterized by its item type.
pub const options_area = @import("options_area.zig");
/// An area wrapper that adds scrolling and button overrides.
pub const scrollable_panel = @import("scrollable_panel.zig");
/// A full-screen window composed of a fixed set of typed tabs.
pub const tabbed_window = @import("tabbed_window.zig");
/// Multi-step wizard window components.
pub const wizard = @import("wizard/wizard_pkg.zig");

/// Creates an options area for the supplied item type.
pub const OptionsArea = options_area.OptionsArea;
/// Creates a bordered modal window for the supplied area type.
pub const ModalWindow = modal_window.ModalWindow;
/// Creates a scrolling panel around the supplied area type.
pub const ScrollablePanel = scrollable_panel.ScrollablePanel;
/// Creates a tabbed window from a compile-time list of area types.
pub const TabbedWindow = tabbed_window.TabbedWindow;
/// A read-only area containing text lines.
pub const TextArea = @import("TextArea.zig");
/// Composes a borrowed main window with owned modal windows.
pub const WindowCompositor = @import("WindowCompositor.zig");

/// A maximal region which can be occupied by a window.
/// This region includes a space for borders.
pub const FULL_SCREEN_REGION: p.Region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);

/// The result of handling a button. Some window can have default `Close` button (a Description
/// window as example), or have another logic to request closing itself (a window with options).
pub const HandleButtonResult = enum {
    /// Means that the window should be closed after handling a button
    close_window,
    /// Means that the window should still be open.
    keep_open,
};

/// A label and optional alternative-action marker for a screen button.
pub const Button = struct {
    label: []const u8,
    has_alternative: bool = false,
};

/// The buttons currently available on the left and right sides of the screen.
pub const Buttons = struct {
    left: ?Button = null,
    right: ?Button = null,

    /// Draws both buttons and hides sides that are not present.
    pub fn draw(self: Buttons, render: g.Render) g.SystemError!void {
        if (self.left) |button| {
            try render.drawLeftButton(button.label, button.has_alternative);
        } else {
            try render.hideLeftButton();
        }
        if (self.right) |button| {
            try render.drawRightButton(button.label, button.has_alternative);
        } else {
            try render.hideRightButton();
        }
    }
};

/// Rebuilds an entity options area while preserving its selected item when possible.
pub fn updateAreaWithItems(
    area: *OptionsArea(g.Entity),
    context: *anyopaque,
    items: g.utils.EntitiesSet,
    formatLine: *const fn (line: *TextArea.Line, context: *anyopaque, item: g.Entity) g.SystemError![]const u8,
    handler: OptionsArea(g.Entity).ButtonHandler,
) g.SystemError!void {
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
        area.selectLine(if (selected_line < area.options.items.len)
            selected_line
        else
            area.options.items.len - 1);
    }
}
