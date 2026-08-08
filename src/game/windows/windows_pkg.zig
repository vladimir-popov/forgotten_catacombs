//! This is a very simple system of windows. Two key concepts exist:
//! areas and windows.
//!
//! The areas are about managing and drawing a content.
//!
//! The windows are about placing the areas somewhere on the screen.
//!
//! Both windows and areas can have a special handlers for buttons. You have
//! to manage the state of both windows and areas in their container manually.
//!
//! The interface of areas is:
//! ```zig
//! /// Should return a label of the `B` (right) button
//! /// if the area has a handler of it. The second boolean parameter
//! /// means should be handler invoked on release (false), or hold (true)
//! // the button.
//! fn button(self: Self) ?struct { []const u8, bool }
//!
//! /// Returns the total lines of this are content.
//! fn totalLines(self: Self) usize
//!
//! /// Returns the zero-based index of the currently selected line or null.
//! fn selectedLine(self: Self) ?usize
//!
//! /// A method to handle a pressed button
//! /// Should return `true` if the 'close' button was pressed, or the content requires closing after
//! /// handling the button.
//! fn handleButton(self: *Self, btn: g.Button) !HandleButtonResult
//!
//! /// Uses the render to draw the area directly to the screen.
//! ///
//! /// - `region` - A region of the screen to draw the content of the area.
//! ///  The first symbol will be drawn at the top left corner of the region.
//! ///  Scrolled lines and lines out of the region will be skipped. Symbols
//! ///  of a line outside the region will be cropped.
//! ///
//! /// - `scrolled` - How many scrolled lines should be skipped.
//! fn draw(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) !void
//! ```
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

pub const ModalWindow = @import("ModalWindow.zig").ModalWindow;
pub const OptionsArea = @import("OptionsArea.zig").OptionsArea;
pub const ScrollableArea = @import("ScrollableArea.zig").ScrollableArea;
pub const TextArea = @import("TextArea.zig");
pub const WindowWithTabs = @import("WindowWithTabs.zig");

pub fn scrollingProgress(scrolled_lines: usize, area_height: usize, max_scroll_count: usize) usize {
    var progress = scrolled_lines * area_height / max_scroll_count;
    // Two corner cases for better UX:
    // 1. Move the scroll after the first scrolling
    if (progress == 0 and scrolled_lines > 0) progress += 1;
    // 2. Do not move the scroll to the end until the last possible line is scrolled
    // (progress become == content_height)
    if (progress == area_height - 1 or progress == area_height)
        progress -= 1;
    return progress;
}

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
/// │              Message              │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn notification(
    alloc: std.mem.Allocator,
    message: []const u8,
    opts: NotificationOptions,
) !ModalWindow(TextArea) {
    var text_area: TextArea = .empty;
    var itr = std.mem.splitScalar(u8, message, '\n');
    while (itr.next()) |msg_line| {
        const line = try text_area.addEmptyLine(alloc);
        const width = g.DISPLAY_COLS - 2;
        const pad = switch (opts.text_align) {
            .left => 0,
            .center => p.diff(msg_line.len, width) / 2,
            .right => p.diff(msg_line.len, width),
        };
        _ = try std.fmt.bufPrint(line[pad..], "{s}", .{msg_line});
    }
    if (opts.title.len > 0)
        return .modalWindowWithTitle(opts.title, text_area, opts.max_region)
    else
        return .modalWindow(text_area, opts.max_region);
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
) !ModalWindow(TextArea) {
    var area: TextArea = .empty;
    if (session.player.id == entity.id) {
        try g.Description.describePlayer(alloc, session.journal, entity, &area);
    } else if (session.registry.has(entity, c.EnemyState)) {
        try g.Description.describeEnemy(alloc, session.journal, entity, &area);
    } else {
        const is_equipped = g.meta.isEquipped(&session.registry, session.player, entity);
        try g.Description.describeItem(alloc, session.journal, entity, is_equipped, &area);
    }
    // A modal window with an entity description should always have the maximal possible width,
    // because all descriptions have fixed length lines
    var window = ModalWindow(TextArea).defaultModalWindow(area);
    window.title_len = (try g.Description.printActualName(&window.title_buffer, session.journal, entity)).len;
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
    comptime Item: type,
    owner: *anyopaque,
) ModalWindow(OptionsArea(Item)) {
    return .{ .scrollable_area = OptionsArea(Item).init(owner, .center) };
}

pub const FormatItemLineFn = *const fn (
    context: *anyopaque,
    line: *TextArea.Line,
    item: g.Entity,
) anyerror![]const u8;

pub fn updateAreaWithItems(
    arena: *std.heap.ArenaAllocator,
    context: *anyopaque,
    items: g.utils.EntitiesSet,
    formatLine: FormatItemLineFn,
    onReleaseButton: OptionsArea(g.Entity).OnReleaseButton,
    onHoldButton: OptionsArea(g.Entity).OnHoldButton,
    area: *ScrollableArea(OptionsArea(g.Entity)),
) !void {
    const selected_line = area.content.selected_line;
    area.content.clearRetainingCapacity();
    var itr = items.iterator();
    while (itr.next()) |item_ptr| {
        var line: TextArea.Line = undefined;
        try area.content.addOption(
            arena.allocator(),
            try formatLine(context, &line, item_ptr.*),
            item_ptr.*,
            onReleaseButton,
            onHoldButton,
        );
    }
    if (area.content.options.items.len > 0) {
        try area.content.selectLine(if (selected_line < area.content.options.items.len)
            selected_line
        else
            area.content.options.items.len - 1);
    }
}
