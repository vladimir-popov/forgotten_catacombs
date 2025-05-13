const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;

const DrawOptions = @This();

/// If true, then the `region` options should be interpret as a maximal, but not as an actually occupied region
is_adaptive: bool,
/// Actual or maximal occupied region (depends on `is_adaptive` option)
region: p.Region,
/// The mode to draw the border. If it's not specified then the border should not be drawn (but a
/// place should be reserved).
border: ?g.DrawingMode,

pub const modal = DrawOptions{
    .border = .normal,
    .is_adaptive = true,
    .region = p.Region.init(1, 2, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS - 2),
};

pub const full_screen = DrawOptions{
    .border = null,
    .is_adaptive = false,
    .region = p.Region.init(1, 1, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS),
};

/// The maximum symbols in a row (few symbols can be reserved for border and/or scroll)
pub fn maxLineSymbols(self: DrawOptions) u8 {
    // -2 for padding; -2 for borders; -1 for scroll.
    return self.region.cols - 5;
}

/// Returns the region that should be occupied (including border) according to the options and actual count of lines.
pub fn actualRegion(self: DrawOptions, actual_rows: u8) p.Region {
    // Count of rows that should be drawn (including border)
    const rows: u8 = if (self.is_adaptive) actual_rows + 2 else self.region.rows; // 2 for border
    return .{
        .top_left = if (rows < self.region.rows)
            self.region.top_left.movedToNTimes(.down, (self.region.rows - rows) / 2)
        else
            self.region.top_left,
        .rows = @min(rows, self.region.rows),
        .cols = self.region.cols,
    };
}
