const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

/// A maximal region which can be occupied by the modal window above this window.
/// This region includes a space for borders.
pub const DEFAULT_MAX_REGION: p.Region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);

pub const Options = struct {
    title: []const u8 = &.{},
    max_region: p.Region = DEFAULT_MAX_REGION,
};

const Self = @This();

title_buffer: [32]u8 = undefined,
title_len: usize,
panel: w.Panel,
region: p.Region,

pub fn initFullScreenText(
    self: *Self,
    alloc: std.mem.Allocator,
    window_title: []const u8,
) !w.TextArea {
    self.region = DEFAULT_MAX_REGION;
    try self.formatTitle("{s}", .{window_title});
    const area = self.panel.initWithText(alloc);
    return area;
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
pub fn initOptions(
    self: *Self,
    alloc: std.mem.Allocator,
    comptime Item: type,
    context: *anyopaque,
    text_align: g.TextAlign,
    opts: Options,
) !w.OptionsArea(Item) {
    self.region = opts.max_region;
    try self.formatTitle("{s}", .{opts.title});
    const area = self.panel.initWithOptions(alloc, Item);
    area.* = .initEmpty(alloc, context, text_align);
    self.shrinkToContent();
    return area;
}

/// Shows a multiline message in the modal window.
/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │               Multi               │
/// │               line                │
/// │              message              │
/// └───────────────────────────────────┘
/// ```
pub fn initNotification(
    self: *Self,
    alloc: std.mem.Allocator,
    message: []const u8,
    opts: Options,
) !void {
    self.region = opts.max_region;
    try self.formatTitle("{s}", .{opts.title});
    const text_area = try self.panel.initWithText(alloc);
    var itr = std.mem.splitScalar(u8, message, '\n');
    while (itr.next()) |msg_line| {
        const line = try text_area.addEmptyLine();
        const width = g.DISPLAY_COLS - 2;
        const pad = p.diff(msg_line.len, width) / 2;
        _ = try std.fmt.bufPrint(line[pad..], "{s}", .{msg_line});
    }
    self.shrinkToContent();
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
pub fn initEntityDescription(
    self: *Self,
    alloc: std.mem.Allocator,
    session: *const g.GameSession,
    entity: g.Entity,
    opts: Options,
) !void {
    self.region = opts.max_region;
    try self.formatTitle("{f}", .{g.Description.actualNameFormatter(session.journal, entity)});
    const text_area = try self.panel.initWithText(alloc);
    if (session.player.id == entity.id) {
        try g.Description.describePlayer(session.journal, entity, text_area);
    } else if (session.registry.has(entity, g.components.EnemyState)) {
        try g.Description.describeEnemy(session.journal, entity, text_area);
    } else {
        const is_equipped = g.meta.isEquipped(&session.registry, session.player, entity);
        try g.Description.describeItem(session.journal, entity, is_equipped, text_area);
    }
}

pub fn deinit(self: *Self) void {
    self.panel.deinit();
}

// this method must be either inline or receive a pointer to the self
pub fn title(self: *const Self) []const u8 {
    return self.title_buffer[0..self.title_len];
}

pub fn formatTitle(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    self.title_len = (try std.fmt.bufPrint(&self.title_buffer, fmt, args)).len;
}

/// Shrinks the window vertically to fit its content.
///
/// The resulting height includes the top and bottom borders and is limited by
/// the current window region. If the content is shorter than the available
/// height, the window is vertically centered within that region.
///
/// Updates the scrollable area's region to match the resized window.
pub fn shrinkToContent(self: *Self) void {
    // Count of rows that should be drawn (including border)
    const rows: usize = self.panel.totalLines() + 2; // 2 for border
    const max_region = self.region;
    self.region = .{
        .top_left = if (rows < max_region.rows)
            max_region.top_left.movedToNTimes(.down, (max_region.rows - rows) / 2)
        else
            max_region.top_left,
        .rows = @min(rows, max_region.rows),
        .cols = max_region.cols,
    };
    self.panel.region = self.region.innerRegion(1, 1, 1, 1);
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    return try self.panel.handleButton(btn);
}

/// Draws the window with a scrollbar and buttons if they are required.
pub fn draw(self: *Self, render: g.Render) !void {
    try self.drawContent(render);
    try self.drawBorder(render);
    try self.drawTitle(render);
    try self.drawButtons(render);
}

/// Draws the title
fn drawTitle(self: *const Self, render: g.Render) !void {
    const padding: u8 = @intCast(self.region.cols - self.title_len);
    const point = self.region.top_left.movedToNTimes(.right, padding / 2);
    const ttl = self.title();
    try render.drawText(ttl, point, .normal);
}

/// Draws the content of its inner scrollable panel
pub fn drawContent(self: *const Self, render: g.Render) !void {
    try self.panel.draw(render);
}

/// Draws the border around its region
fn drawBorder(self: *const Self, render: g.Render) !void {
    try render.drawBorder(self.region);
}

/// Draws the border around its region
pub fn drawButtons(self: *const Self, render: g.Render) !void {
    if (self.panel.leftButton()) |btn| {
        try render.drawLeftButton(btn.text, btn.has_alternatives);
    } else {
        try render.hideLeftButton();
    }
    if (self.panel.rightButton()) |btn| {
        try render.drawRightButton(btn.text, btn.has_alternatives);
    } else {
        try render.hideRightButton();
    }
}

/// Fills the region of the window either from the buffer, or just fill it with spaces.
pub fn hide(self: *Self, render: g.Render, hide_mode: w.HideMode) !void {
    switch (hide_mode) {
        .from_buffer => try render.redrawRegionFromSceneBuffer(self.region),
        .fill_region => try render.fillRegion(g.Render.default_filler, .normal, self.region),
    }
}
