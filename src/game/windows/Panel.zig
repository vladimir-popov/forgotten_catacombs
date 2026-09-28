const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const Self = @This();

arena: std.heap.ArenaAllocator,
area: w.Area,
scrolled_lines: usize = 0,

pub fn initWithText(self: *Self, alloc: std.mem.Allocator) !*w.TextArea {
    self.scrolled_lines = 0;
    self.arena = std.heap.ArenaAllocator.init(alloc);
    const text_area = try self.arena.allocator().create(w.TextArea);
    errdefer self.arena.deinit();
    text_area.* = .initEmpty(self.arena.allocator());
    self.area = text_area.area();
    return text_area;
}

pub fn initWithOptions(
    self: *Self,
    alloc: std.mem.Allocator,
    comptime Item: type,
    context: *anyopaque,
    text_align: g.TextAlign,
) !*w.OptionsArea(Item) {
    self.scrolled_lines = 0;
    self.arena = std.heap.ArenaAllocator.init(alloc);
    const options_area = try self.arena.allocator().create(w.OptionsArea(Item));
    errdefer self.arena.deinit();
    options_area.* = .initEmpty(self.arena.allocator(), context, text_align);
    self.area = options_area.area();
    return options_area;
}

pub fn deinit(self: *Self) void {
    self.arena.deinit();
}

pub fn isScrollRequired(self: *const Self, region: p.Region) bool {
    return self.area.totalLines() > region.rows;
}

fn maxScrollingCount(self: *const Self, region: p.Region) usize {
    return self.area.totalLines() -| (region.rows);
}

pub fn totalLines(self: Self) usize {
    return self.area.totalLines();
}

pub fn clearRetainingCapacity(self: *Self) void {
    self.area.clearRetainingCapacity();
}

pub fn leftButton(self: *const Self) ?w.Button {
    return self.area.leftButton();
}

pub fn rightButton(self: *const Self) ?w.Button {
    return self.area.rightButton();
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    if (try self.area.handleButton(btn) == .close_window)
        return .close_window;

    switch (btn.game_button) {
        .up => {
            if (self.scrolled_lines > 0)
                self.scrolled_lines -= 1;
        },
        .down => {
            // if (self.scrolled_lines < self.maxScrollingCount())
            if (self.scrolled_lines < self.area.totalLines())
                self.scrolled_lines += 1;
        },
        else => {},
    }
    return .keep_open;
}

pub fn draw(self: *const Self, render: g.Render, region: p.Region) !void {
    // Draw the scrollbar
    if (self.isScrollRequired(region)) {
        const progress = scrollingProgress(self.scrolled_lines, region.rows, self.maxScrollingCount(region));
        var point = region.topRight();
        for (0..region.rows) |i| {
            if (i == progress)
                try render.runtime.drawSprite('▒', point, .normal)
            else
                try render.runtime.drawSprite('░', point, .normal);
            point.move(.down);
        }
    }
    // Draw the content inside the region excluding a space for the scrollbar
    const right_pad: u8 = if (self.isScrollRequired(region)) 1 else 0;
    try self.area.draw(render, region.innerRegion(0, right_pad, 0, 0), self.scrolled_lines);
}

fn scrollingProgress(scrolled_lines: usize, area_height: usize, max_scroll_count: usize) usize {
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
