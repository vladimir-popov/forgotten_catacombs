//! The Viewport is an area with visible part of the dungeon.
const std = @import("std");
const cp = @import("codepoints.zig");
const g = @import("game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.viewport);

const Viewport = @This();

/// The region which should be displayed.
/// The top left corner is in to the dungeon's coordinates.
region: p.Region,
// Padding for the player's sprite to keep some space between the player and viewport borders
rows_pad: u8,
cols_pad: u8,

pub fn init(rows: u8, cols: u8) Viewport {
    return .{
        .region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols },
        .rows_pad = @intFromFloat(@as(f16, @floatFromInt(rows)) * 0.2),
        .cols_pad = @intFromFloat(@as(f16, @floatFromInt(cols)) * 0.2),
    };
}

pub fn subscriber(self: *Viewport) g.events.Subscriber {
    return .{ .context = self, .onEvent = onEntityMoved };
}

fn onEntityMoved(ptr: *anyopaque, event: g.events.Event) !void {
    if (event.get(.entity_moved) == null) return;
    if (!event.entity_moved.is_player) return;
    const self: *Viewport = @ptrCast(@alignCast(ptr));
    const entity_moved = event.entity_moved;

    // keep player on the screen:
    switch (entity_moved.target) {
        .new_place => |place| self.centeredAround(place),
        .direction => |direction| {
            const inner_region = self.innerRegion();
            const new_place = entity_moved.moved_from.movedTo(direction);
            if (direction == .up and new_place.row < inner_region.top_left.row)
                self.move(direction);
            if (direction == .down and new_place.row > inner_region.bottomRightRow())
                self.move(direction);
            if (direction == .left and new_place.col < inner_region.top_left.col)
                self.move(direction);
            if (direction == .right and new_place.col > inner_region.bottomRightCol())
                self.move(direction);
        },
    }
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
    return .{ .row = point.row - self.region.top_left.row + 1, .col = point.col - self.region.top_left.col + 1 };
}

pub inline fn move(self: *Viewport, direction: p.Direction) void {
    self.moveNTimes(direction, 1);
}

pub fn moveNTimes(self: *Viewport, direction: p.Direction, n: u8) void {
    switch (direction) {
        .up => {
            if (self.region.top_left.row > 1) {
                const n0 = @min(n, self.region.top_left.row - 1);
                self.region.top_left.row -= n0;
            }
        },
        .down => {
            if (self.region.bottomRightRow() < g.DUNGEON_ROWS) {
                const n0 = @min(n, g.DUNGEON_ROWS - self.region.bottomRightRow());
                self.region.top_left.row += n0;
            }
        },
        .left => {
            if (self.region.top_left.col > 1) {
                const n0 = @min(n, self.region.top_left.col - 1);
                self.region.top_left.col -= n0;
            }
        },
        .right => {
            if (self.region.bottomRightCol() < g.DUNGEON_COLS) {
                const n0 = @min(n, g.DUNGEON_COLS - self.region.bottomRightCol());
                self.region.top_left.col += n0;
            }
        },
    }
}
