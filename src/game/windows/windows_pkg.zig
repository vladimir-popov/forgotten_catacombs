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

/// To hide a window something should be drawn inside its region.
/// The easiest way is drawing underlying layer again (for example the whole scene, or a window
/// under the current),but it's on optimal way. Usually we have to particular options:
///  - `from_buffer` - redraw inside the region a content from the inner buffer of the render;
///  - `fill_region` - draw inside the region an empty space.
/// The first one is actual when a window is above the scene, the second - when the window is above
/// another window.
pub const HideMode = enum { from_buffer, fill_region };

/// The result of handling a button. Some window can have default `Close` button (a Description
/// window as example), or have another logic to request closing itself (a window with options).
pub const HandleButtonResult = enum {
    /// If the 'close' button was pressed, or the content requires closing after
    /// handling the button.
    close_window,
    /// A button was handled, but the window should still be open.
    keep_open,
};

pub const wizard = @import("wizard/wizard_pkg.zig");

pub const Area = @import("Area.zig");
pub const Button = @import("Button.zig");
pub const ModalWindow = @import("ModalWindow.zig");
pub const OptionsArea = @import("OptionsArea.zig").OptionsArea;
pub const Panel = @import("Panel.zig");
pub const TabbedWindow = @import("TabbedWindow.zig");
pub const TextArea = @import("TextArea.zig");
pub const WindowComposer = @import("WindowComposer.zig").WindowComposer;

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
