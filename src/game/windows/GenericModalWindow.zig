const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const Self = @This();

/// Type-erased interface for an area used by a generic panel.
pub const VTable = struct {
    /// Returns the total lines of this are content.
    totalLinesFn: *const fn (ptr: *anyopaque) usize,

    /// Returns the zero-based index of the currently selected line or null.
    selectedLineFn: *const fn (ptr: *anyopaque) ?usize,

    /// A method to handle a pressed button
    /// Should return `true` if the 'close' button was pressed, or the content requires closing after
    /// handling the button.
    handleButtonFn: *const fn (ptr: *anyopaque, btn: g.Button) g.SystemError!w.HandleButtonResult,

    /// Uses the render to draw the area directly to the screen.
    ///
    /// - `region` - A region of the screen to draw the content of the area.
    ///  The first symbol will be drawn at the top left corner of the region.
    ///  Scrolled lines and lines out of the region will be skipped. Symbols
    ///  of a line outside the region will be cropped.
    ///
    /// - `scrolled` - How many scrolled lines should be skipped.
    drawFn: *const fn (ptr: *anyopaque, render: g.Render, region: p.Region, scrolled: usize) g.SystemError!void,

    clearRetainingCapacityFn: *const fn (ptr: *anyopaque) void,

    leftButtonFn: *const fn (ptr: *anyopaque) ?w.Button,

    rightButtonFn: *const fn (ptr: *anyopaque) ?w.Button,
};

underlying: *anyopaque,
vtable: *const VTable,

/// Returns the number of content lines.
pub fn totalLines(self: Self) usize {
    return self.vtable.totalLinesFn(self.underlying);
}

/// Returns the selected line, if the wrapped area supports selection.
pub fn selectedLine(self: Self) ?usize {
    return self.vtable.selectedLineFn(self.underlying);
}

/// Clears the wrapped area while retaining its capacity.
pub fn clearRetainingCapacity(self: *Self) void {
    self.vtable.clearRetainingCapacityFn(self.underlying);
}

/// Returns the wrapped area's left button.
pub fn leftButton(self: *const Self) ?w.Button {
    return self.vtable.leftButtonFn(self.underlying);
}

/// Returns the wrapped area's right button.
pub fn rightButton(self: *const Self) ?w.Button {
    return self.vtable.rightButtonFn(self.underlying);
}

/// Forwards a button to the wrapped area.
pub fn handleButton(self: *Self, btn: g.Button) g.SystemError!w.HandleButtonResult {
    return self.vtable.handleButtonFn(self.underlying, btn);
}

/// Draws the wrapped area in `region` at the supplied scroll offset.
pub fn draw(self: *const Self, render: g.Render, region: p.Region, scrolled: usize) g.SystemError!void {
    return self.vtable.drawFn(self.underlying, render, region, scrolled);
}

/// Builds a vtable for a concrete area type.
pub fn vtableFor(comptime T: type) *const VTable {
    return &struct {
        fn totalLinesFn(ptr: *anyopaque) usize {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.totalLines();
        }
        fn selectedLineFn(ptr: *anyopaque) ?usize {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.selectedLine();
        }
        fn clearRetainingCapacityFn(ptr: *anyopaque) void {
            const self: *T = @ptrCast(@alignCast(ptr));
            self.clearRetainingCapacity();
        }
        fn handleButtonFn(ptr: *anyopaque, btn: g.Button) g.SystemError!w.HandleButtonResult {
            const self: *T = @ptrCast(@alignCast(ptr));
            return try self.handleButton(btn);
        }
        fn drawFn(ptr: *anyopaque, render: g.Render, region: p.Region, scrolled: usize) g.SystemError!void {
            const self: *T = @ptrCast(@alignCast(ptr));
            try self.draw(render, region, scrolled);
        }
        fn leftButtonFn(ptr: *anyopaque) ?w.Button {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.leftButton();
        }
        fn rightButtonFn(ptr: *anyopaque) ?w.Button {
            const self: *T = @ptrCast(@alignCast(ptr));
            return self.rightButton();
        }

        const vtable: VTable = .{
            .totalLinesFn = totalLinesFn,
            .selectedLineFn = selectedLineFn,
            .clearRetainingCapacityFn = clearRetainingCapacityFn,
            .handleButtonFn = handleButtonFn,
            .drawFn = drawFn,
            .leftButtonFn = leftButtonFn,
            .rightButtonFn = rightButtonFn,
        };
    }.vtable;
}

/// A no-op area implementation for an empty panel.
pub const empty: Self = .{
    .underlying = undefined,
    .vtable = &.{
        .totalLinesFn = Empty.totalLines,
        .selectedLineFn = Empty.selectedLine,
        .clearRetainingCapacityFn = Empty.clearRetainingCapacity,
        .handleButtonFn = Empty.handleButton,
        .drawFn = Empty.draw,
        .leftButtonFn = Empty.leftButton,
        .rightButtonFn = Empty.rightButton,
    },
};

pub const Empty = struct {
    fn totalLines(_: *anyopaque) usize {
        return 0;
    }

    fn selectedLine(_: *anyopaque) ?usize {
        return null;
    }

    fn handleButton(_: *anyopaque, _: g.Button) w.HandleButtonResult {
        return .keep_open;
    }

    fn draw(_: *const anyopaque, render: g.Render, region: p.Region, _: usize) g.Runtime.Error!void {
        try render.fillRegion(g.Render.default_filler, .normal, region);
    }

    fn clearRetainingCapacity(_: *anyopaque) void {}

    fn leftButton(_: *anyopaque) ?w.Button {
        return null;
    }
    fn rightButton(_: *anyopaque) ?w.Button {
        return null;
    }
};
