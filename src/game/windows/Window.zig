const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

/// A maximal region which can be occupied by the modal window.
/// This region includes a space for borders.
pub const DEFAULT_MAX_REGION: p.Region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);

const Self = @This();

content_arena: std.heap.ArenaAllocator,
title_buffer: [32]u8 = undefined,
title_len: usize = 0,
scrollable_area: w.ScrollableArea(w.Area),
// The region on the screen occupied by this window. Includes space for the title and border.
region: p.Region,

pub fn init(alloc: std.mem.Allocator, max_region: p.Region) Self {
    return .{
        .content_arena = .init(alloc),
        .region = max_region,
        .scrollable_area = .{ .content = .empty, .region = max_region.innerRegion(1, 1, 1, 1) },
    };
}

pub fn deinit(self: *Self) void {
    self.content_arena.deinit();
}

pub fn allocator(self: *Self) std.mem.Allocator {
    return self.content_arena.allocator();
}

pub fn shrinkToContent(self: *Self) void {
    // Count of rows that should be drawn (including border)
    const rows: usize = self.scrollable_area.totalLines() + 2; // 2 for border
    const max_region = self.region;
    self.region = .{
        .top_left = if (rows < max_region.rows)
            max_region.top_left.movedToNTimes(.down, (max_region.rows - rows) / 2)
        else
            max_region.top_left,
        .rows = @min(rows, max_region.rows),
        .cols = max_region.cols,
    };
    self.scrollable_area.region = self.region.innerRegion(1, 1, 1, 1);
}

// this method must be either inline or receive a pointer to the self
pub inline fn title(self: Self) []const u8 {
    return self.title_buffer[0..self.title_len];
}

pub fn formatTitle(self: *Self, comptime fmt: []const u8, args: anytype) !void {
    self.title_len = (try std.fmt.bufPrint(&self.title_buffer, fmt, args)).len;
}

/// Returns a pointer to a not initialized Area.
pub fn changeContent(self: *Self, comptime Area: type) !*Area {
    _ = self.content_arena.reset(.retain_capacity);
    const area = try self.content_arena.allocator().create(Area);
    self.scrollable_area.content = area.area();
    return area;
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    return try self.scrollable_area.handleButton(btn);
}

/// Draws the window with a scrollbar and buttons if they are required.
pub fn draw(self: *const Self, render: g.Render) !void {
    // Draw the content
    try self.scrollable_area.draw(render);
    // Draw the border
    try render.drawBorder(self.region);
    // Draw the title
    const padding: u8 = @intCast(self.region.cols - self.title_len);
    const point = self.region.top_left.movedToNTimes(.right, padding / 2);
    const ttl = self.title();
    try render.drawText(ttl, point, .normal);
}

/// Fills the region of the window either from the buffer, or just fill it with spaces.
pub fn hide(self: *Self, render: g.Render, hide_mode: w.HideMode) !void {
    switch (hide_mode) {
        .from_buffer => try render.redrawRegionFromSceneBuffer(self.region),
        .fill_region => try render.fillRegion(g.Render.default_filler, .normal, self.region),
    }
}
