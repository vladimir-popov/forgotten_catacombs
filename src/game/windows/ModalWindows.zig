const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const Self = @This();

windows: std.ArrayList(w.Window) = .empty,
/// The biggest region can be occupied by a window.
max_region: p.Region,
is_redrawing_required: bool = true,

pub fn empty(max_region: p.Region) Self {
    return .{ .max_region = max_region };
}

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    self.windows.deinit(alloc);
}

/// Returns the last window in the list
pub fn topWindow(self: Self) ?*w.Window {
    if (self.windows.items.len == 0) return null;
    return &self.windows.items[self.windows.items.len - 1];
}

/// Creates an new window on heap, initialize it and adds to the `windows`.
pub fn createOnTop(self: *Self, alloc: std.mem.Allocator) !*w.Window {
    const window = try self.windows.addOne(alloc);
    window.* = .init(alloc, self.max_region);
    return window;
}

pub fn handleButton(self: *Self, btn: g.Button) !void {
    self.is_redrawing_required = true;
    if (self.topWindow()) |window| {
        const current_idx = self.windows.items.len - 1;
        if (try window.handleButton(btn) == .close_window) {
            self.windows.items[current_idx].deinit();
            self.windows.replaceRangeAssumeCapacity(current_idx, 1, &.{});
        }
    }
}

pub fn draw(self: *Self, render: g.Render) !void {
    if (!self.is_redrawing_required) return;
    defer self.is_redrawing_required = false;

    try render.fillRegion(g.Render.default_filler, .normal, self.max_region);
    for (self.windows.items) |*window| {
        try window.draw(render);
    }
}

pub inline fn isEmpty(self: Self) bool {
    return self.windows.items.len == 0;
}

pub inline fn nonEmpty(self: Self) bool {
    return self.windows.items.len > 0;
}
