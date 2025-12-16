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
//! /// if the area has a handler of it. The secon boolean parameter
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
//! fn handleButton(self: *Self, btn: g.Button) !void
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
    if (args.session.player.id == args.entity.id) {
        try g.descriptions.describePlayer(args.alloc, args.session.journal, args.entity, &area);
    } else {
        try g.descriptions.describeEntity(args.alloc, args.session.journal, args.entity, &area);
    }
    var window = if (args.max_region) |mr|
        w.ModalWindow(TextArea).init(area, mr)
    else
        w.ModalWindow(TextArea).default(area);
    window.title_len = (try g.descriptions.printName(&window.title_buffer, args.session.journal, args.entity)).len;
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
