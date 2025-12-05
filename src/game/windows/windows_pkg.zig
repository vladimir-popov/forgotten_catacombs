//! This is a very simple system of windows. Two key concepts exist:
//! areas and windows. The areas are about managing and drawing a content.
//! The windows are about placing the areas somewhere on the screen. Both windows
//! and areas can have a special handlers for buttons. Additionally, windows
//! should handle closing, returning `true` from the button handler.
//! You have to manage state of both windows and areas in their container manually.
//!
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

/// To hide a window something should be drawn inside its region.
/// The easiest way is drawing underlying layer again (for example the whole scene, or a window
/// under the current),but it's on optimal way. Usually we have to particular options:
///  - `from_buffer` - redraw inside the region a content from the inner buffer of the render;
///  - `fill_region` - draw inside the region an empty space.
/// The first one is actual when a window is above the scene, the second - when the window is above
/// another window.
pub const HideMode = enum { from_buffer, fill_region };

pub const ModalWindow = @import("ModalWindow.zig").ModalWindow;
pub const OptionsArea = @import("OptionsArea.zig").OptionsArea;
pub const ScrollableAre = @import("ScrollableAre.zig").ScrollableAre;
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

/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │              Message              │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn notification(alloc: std.mem.Allocator, message: []const u8) !ModalWindow(TextArea) {
    var text_area: TextArea = .empty;
    const line = try text_area.addEmptyLine(alloc);
    const width = g.DISPLAY_COLS - 2;
    const pad = p.diff(usize, message.len, width) / 2;
    _ = try std.fmt.bufPrint(line[pad..], "{s}", .{message});
    return .default(text_area);
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
pub fn entityDescription(args: struct {
    alloc: std.mem.Allocator,
    session: *const g.GameSession,
    entity: g.Entity,
    max_region: ?p.Region = null,
}) !ModalWindow(TextArea) {
    var area: TextArea = .empty;
    try g.meta.describe(args.session.journal, args.alloc, args.entity, &area);
    var window = if (args.max_region) |mr|
        w.ModalWindow(TextArea).init(area, mr)
    else
        w.ModalWindow(TextArea).default(area);
    window.title_len = (try g.meta.printName(&window.title_buffer, args.session.journal, args.entity)).len;
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
    return .{ .content = OptionsArea(Item).init(owner, .center) };
}
