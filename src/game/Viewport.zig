const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;

const log = std.log.scoped(.viewport);

const Viewport = @This();

pub const DrawableSymbol = struct {
    codepoint: g.Codepoint,
    mode: g.Render.DrawingMode,
};

const SceneBuffer = struct {
    const VersionedCell = struct {
        symbol: DrawableSymbol,
        z_order: u2,
        ver: u1,
        is_changed: bool,
    };
    pub const Row = []VersionedCell;

    rows: []Row,
    arena: *std.heap.ArenaAllocator,
    current_iteration: u1 = 1,

    pub fn init(alloc: std.mem.Allocator, rows: u8, cols: u8) !SceneBuffer {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        const arena_alloc = arena.allocator();
        var self = SceneBuffer{ .arena = arena, .rows = try arena_alloc.alloc(Row, rows) };
        for (0..rows) |r| {
            self.rows[r] = try arena_alloc.alloc(VersionedCell, cols);
        }
        self.reset();
        return self;
    }

    pub fn deinit(self: *SceneBuffer) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    pub fn reset(self: *SceneBuffer) void {
        self.current_iteration = 1;
        for (0..self.rows.len) |r| {
            for (self.rows[r]) |*cell| {
                cell.symbol.codepoint = 0;
                cell.z_order = 0;
                cell.ver = 0;
                cell.is_changed = false;
            }
        }
    }

    fn dumpToLog(self: SceneBuffer) void {
        if (std.log.logEnabled(.debug, .viewport)) {
            // the biggest possible size of the viewport (in case when all codepoints < 255)
            var buf: [g.Dungeon.ROWS * (g.Dungeon.COLS + 1) + 1]u8 = undefined;
            var writer = std.io.fixedBufferStream(&buf);
            self.write(writer.writer().any()) catch unreachable;
            log.debug("\n{s}", .{buf});
        }
    }

    fn write(self: SceneBuffer, writer: std.io.AnyWriter) !void {
        var buf: [4]u8 = undefined;
        for (self.rows) |row| {
            for (row) |cell| {
                if (!cell.is_changed) {
                    try writer.writeByte(' ');
                    continue;
                }

                if (cell.symbol.codepoint < 255) {
                    try writer.writeByte(@intCast(cell.symbol.codepoint));
                } else {
                    const len = try std.unicode.utf8Encode(cell.symbol.codepoint, &buf);
                    _ = try writer.write(buf[0..len]);
                }
            }
            try writer.writeByte('\n');
        }
        try writer.writeByte(0);
    }
};

pub const CellIterator = struct {
    buffer: *SceneBuffer,
    r_idx: u8 = 0,
    c_idx: u8 = 0,

    pub fn next(self: *CellIterator) ?struct { p.Point, DrawableSymbol } {
        while (true) {
            defer self.c_idx += 1;

            if (self.c_idx == self.buffer.rows[0].len) {
                self.r_idx += 1;
                self.c_idx = 0;
            }
            if (self.r_idx == self.buffer.rows.len) {
                self.buffer.current_iteration +%= 1;
                return null;
            }

            const cell = &self.buffer.rows[self.r_idx][self.c_idx];
            if (cell.is_changed) {
                return .{ .{ .row = self.r_idx + 1, .col = self.c_idx + 1 }, cell.symbol };
            }
        }
    }
};

/// The region which should be displayed.
/// The top left corner is related to the dungeon.
region: p.Region,
// Padding for the player's sprite
rows_pad: u8,
cols_pad: u8,
buffer: SceneBuffer,

pub fn init(alloc: std.mem.Allocator, rows: u8, cols: u8) !Viewport {
    return .{
        .region = .{ .top_left = .{ .row = 1, .col = 1 }, .rows = rows, .cols = cols },
        .rows_pad = @intFromFloat(@as(f16, @floatFromInt(rows)) * 0.2),
        .cols_pad = @intFromFloat(@as(f16, @floatFromInt(cols)) * 0.2),
        .buffer = try SceneBuffer.init(alloc, rows, cols),
    };
}

pub fn deinit(self: *Viewport) void {
    self.buffer.deinit();
}

pub fn setSymbol(
    self: Viewport,
    point_on_viewport: p.Point,
    codepoint: g.Codepoint,
    mode: g.Render.DrawingMode,
    z_order: u2,
) void {
    std.debug.assert(point_on_viewport.row > 0);
    std.debug.assert(point_on_viewport.col > 0);
    std.debug.assert(point_on_viewport.row <= self.buffer.rows.len);
    std.debug.assert(point_on_viewport.col <= self.buffer.rows[0].len);

    const cell = &self.buffer.rows[point_on_viewport.row - 1][point_on_viewport.col - 1];
    defer cell.ver = self.buffer.current_iteration;

    if (cell.ver != self.buffer.current_iteration) {
        cell.is_changed = false;
    }

    // if the symbol is not changed from the previous iteration, the version
    // of the cell should not be changed
    if (cell.symbol.codepoint == codepoint and cell.symbol.mode == mode) return;

    // if the new symbol is under the existed at the same iteration, do nothing too
    if (cell.ver == self.buffer.current_iteration and cell.z_order > z_order and mode == .normal) return;

    cell.symbol = .{ .codepoint = codepoint, .mode = mode };
    cell.z_order = z_order;
    cell.is_changed = true;
}

pub fn changedSymbols(self: *Viewport) CellIterator {
    // self.buffer.dumpToLog();
    return .{ .buffer = &self.buffer };
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
