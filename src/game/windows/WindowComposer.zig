const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

/// Composes the main window with optional modal windows to draw them efficiently.
///
/// The `MainWindow` should implement  the interface:
///
/// ```zig
/// pub fn handleButton(self: *MainWindow, btn: g.Button) !w.HandleButtonResult
/// pub fn draw(self: *MainWindow, render: g.Render) !void
/// ```
///
pub fn WindowComposer(comptime MainWindow: type) type {
    return struct {
        const Self = @This();

        max_modal_region: p.Region,
        main_window: MainWindow,
        modal_windows: [3]w.ModalWindow = undefined,
        modal_windows_count: usize = 0,
        is_redrawing_required: bool = true,

        pub fn init(main_window: MainWindow, max_modal_region: p.Region) Self {
            return .{ .main_window = main_window, .max_modal_region = max_modal_region };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        /// Creates a new uninitialized window on top of the others and returns a pointer to it.
        pub fn newModalWindow(self: *Self) !*w.ModalWindow {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            self.modal_windows_count += 1;
            return &self.modal_windows[self.modal_windows_count - 1];
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            self.is_redrawing_required = true;
            if (self.modal_windows_count > 0) {
                const idx = self.modal_windows_count - 1;
                if (try self.modal_windows[idx].handleButton(btn) == .close_window) {
                    self.modal_windows[idx].deinit();
                    self.modal_windows_count -= 1;
                }
                return .keep_open;
            } else {
                return self.main_window.handleButton(btn);
            }
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            if (!self.is_redrawing_required) return;
            defer self.is_redrawing_required = false;

            try self.main_window.draw(render);
            for (0 .. self.modal_windows_count) |idx| {
                try self.modal_windows[idx].draw(render);
            }
        }
    };
}
