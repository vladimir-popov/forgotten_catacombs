const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const Self = @This();

pub const empty: Self = .{};

windows: std.ArrayList(w.Window) = .empty,

pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
    self.windows.deinit(alloc);
}

pub fn topWindow(self: Self) ?*w.Window {
    if (self.windows.items.len == 0) return null;
    return &self.windows.items[self.windows.items.len - 1];
}

/// Creates an new window on heap, initialize it and adds to the `windows`.
pub fn createOnTop(self: *Self, alloc: std.mem.Allocator, max_region: p.Region) !*w.Window {
    const window = try self.windows.addOne(alloc);
    window.* = .init(alloc, max_region);
    return window;
}

pub fn handleButton(self: *Self, btn: g.Button) !void {
    if (self.topWindow()) |window| {
        const current_idx = self.windows.items.len - 1;
        if (try window.handleButton(btn) == .close_window) {
            self.windows.items[current_idx].deinit();
            self.windows.replaceRangeAssumeCapacity(current_idx, 1, &.{});
        }
    }
}

pub fn draw(self: Self, render: g.Render) !void {
    if (self.topWindow()) |window| {
        try window.draw(render);
    }
}

pub inline fn isEmpty(self: Self) bool {
    return self.windows.items.len == 0;
}

pub inline fn nonEmpty(self: Self) bool {
    return self.windows.items.len > 0;
}
