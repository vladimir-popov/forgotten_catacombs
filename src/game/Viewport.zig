const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

const Viewport = @This();

/// The region which should be displayed.
/// The top left corner is related to the dungeon.
region: p.Region,
// Padding for the player's sprite
rows_pad: u8,
cols_pad: u8,

pub fn deinit(_: *@This()) void {}

pub fn init(rows: u8, cols: u8) Viewport {
    return .{
        .region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols },
        .rows_pad = @intFromFloat(@as(f16, @floatFromInt(rows)) * 0.2),
        .cols_pad = @intFromFloat(@as(f16, @floatFromInt(cols)) * 0.2),
    };
}

pub fn subscriber(self: *Viewport) g.events.Subscriber(g.events.EntityMoved) {
    return .{ .context = self, .onEvent = onEntityMoved };
}

fn onEntityMoved(ptr: *anyopaque, event: g.events.EntityMoved) !void {
    if (!event.is_player) return;
    const self: *Viewport = @ptrCast(@alignCast(ptr));

    // keep player on the screen:
    const inner_region = self.innerRegion();
    if (event.direction == .up and event.to.row < inner_region.top_left.row)
        self.move(event.direction);
    if (event.direction == .down and event.to.row > inner_region.bottomRightRow())
        self.move(event.direction);
    if (event.direction == .left and event.to.col < inner_region.top_left.col)
        self.move(event.direction);
    if (event.direction == .right and event.to.col > inner_region.bottomRightCol())
        self.move(event.direction);
}

/// Moves the screen to have the point in the center.
/// The point is some place in the dungeon.
pub fn centeredAround(self: *Viewport, point: p.Point) void {
    self.region.top_left = .{
        .row = if (point.row > self.region.rows / 2) point.row - self.region.rows / 2 else 1,
        .col = if (point.col > self.region.cols / 2) point.col - self.region.cols / 2 else 1,
    };
}

/// Try to keep the player inside this region
pub inline fn innerRegion(self: Viewport) p.Region {
    var inner_region = self.region;
    inner_region.top_left.row += self.rows_pad;
    inner_region.top_left.col += self.cols_pad;
    inner_region.rows -= 2 * self.rows_pad;
    inner_region.cols -= 2 * self.cols_pad;
    return inner_region;
}

/// Gets the point in the dungeon and return its coordinates on the screen.
pub inline fn relative(self: Viewport, point: p.Point) p.Point {
    return .{ .row = point.row - self.region.top_left.row, .col = point.col - self.region.top_left.col };
}

pub fn move(self: *Viewport, direction: p.Direction) void {
    switch (direction) {
        .up => {
            if (self.region.top_left.row > 1)
                self.region.top_left.row -= 1;
        },
        .down => {
            if (self.region.bottomRightRow() < g.Dungeon.ROWS)
                self.region.top_left.row += 1;
        },
        .left => {
            if (self.region.top_left.col > 1)
                self.region.top_left.col -= 1;
        },
        .right => {
            if (self.region.bottomRightCol() < g.Dungeon.COLS)
                self.region.top_left.col += 1;
        },
    }
}
