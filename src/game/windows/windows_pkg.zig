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

pub const Area = @import("Area.zig");
pub const Button = @import("Button.zig");
pub const ModalWindows = @import("ModalWindows.zig");
pub const OptionsArea = @import("OptionsArea.zig").OptionsArea;
pub const ScrollableArea = @import("ScrollableArea.zig").ScrollableArea;
pub const TabbedWindow = @import("TabbedWindow.zig");
pub const TextArea = @import("TextArea.zig");
pub const Window = @import("Window.zig");

pub const NotificationOptions = struct {
    title: []const u8 = &.{},
    max_region: p.Region = .init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS),
    text_align: g.TextAlign = .center,
};

/// Shows a multiline message in the modal window.
/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │               Multi               │
/// │               line                │
/// │              message              │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn notification(
    alloc: std.mem.Allocator,
    message: []const u8,
    opts: NotificationOptions,
) !Window {
    var window = Window.init(alloc, opts.max_region);
    try window.formatTitle("{s}", .{opts.title});

    var text_area = try window.changeContent(TextArea);
    text_area.* = .initEmpty(window.allocator());
    var itr = std.mem.splitScalar(u8, message, '\n');
    while (itr.next()) |msg_line| {
        const line = try text_area.addEmptyLine();
        const width = g.DISPLAY_COLS - 2;
        const pad = switch (opts.text_align) {
            .left => 0,
            .center => p.diff(msg_line.len, width) / 2,
            .right => p.diff(msg_line.len, width),
        };
        _ = try std.fmt.bufPrint(line[pad..], "{s}", .{msg_line});
    }
    window.shrinkToContent();
    return window;
}

/// Approximate example:
/// ```
/// ┌───────────────Club────────────────┐
/// │A gnarled piece of wood, scarred   │
/// │from use. Deals blunt damage.      │
/// │Cheap and easy to use.             │
/// │                                   │
/// │Damage: cutting 2-3                │
/// │Weight: 3                          │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn entityDescription(
    alloc: std.mem.Allocator,
    session: *const g.GameSession,
    entity: g.Entity,
) !Window {
    var window = Window.init(alloc, Window.DEFAULT_MAX_REGION);
    try window.formatTitle("{f}", .{g.Description.actualNameFormatter(session.journal, entity)});

    const area: *TextArea = try window.changeContent(TextArea);
    area.* = .initEmpty(window.allocator());
    if (session.player.id == entity.id) {
        try g.Description.describePlayer(session.journal, entity, area);
    } else if (session.registry.has(entity, c.EnemyState)) {
        try g.Description.describeEnemy(session.journal, entity, area);
    } else {
        const is_equipped = g.meta.isEquipped(&session.registry, session.player, entity);
        try g.Description.describeItem(session.journal, entity, is_equipped, area);
    }
    return window;
}

/// Example:
/// ```
/// ┌──────────────Title───────────────┐
/// │              Option              │
/// │░░░░░░░░░░░░░ Option ░░░░░░░░░░░░░│
/// │              Option              │
/// └──────────────────────────────────┘
///═══════════════════════════════════════
///                          Close Choose
/// ```
pub fn options(
    alloc: std.mem.Allocator,
    comptime Item: type,
    owner: *anyopaque,
) !Window {
    var window = try Window.initFullScreen(alloc);
    _ = try window.createArea(OptionsArea(Item), .init(owner, .center));
    return window;
}

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
        try area.addOption(
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
