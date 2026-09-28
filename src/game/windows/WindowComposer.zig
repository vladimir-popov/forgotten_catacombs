const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

/// Composes the main window with optional modal windows to draw them efficiently.
///
/// The `MainWindow` should implement the interface:
///
/// ```zig
/// pub fn handleButton(self: *MainWindow, btn: g.Button) !w.HandleButtonResult
/// pub fn draw(self: *MainWindow, render: g.Render) !void
/// ```
///
pub fn WindowComposer(comptime MainWindow: type) type {
    return struct {
        const Self = @This();

        main_window: *MainWindow,
        modal_windows: [3]w.ModalWindow = undefined,
        max_modal_region: p.Region = w.ModalWindow.DEFAULT_MAX_REGION,
        modal_windows_count: usize = 0,
        is_redrawing_required: bool = true,

        pub fn init(main_window: *MainWindow, max_modal_region: p.Region) Self {
            return .{ .main_window = main_window, .max_modal_region = max_modal_region };
        }

        /// Releases all modal windows owned by the composer.
        ///
        /// Does not deinitialize `main_window`; it is borrowed from the caller.
        pub fn deinit(self: *Self) void {
            for (0..self.modal_windows_count) |idx| {
                try self.modal_windows[idx].deinit();
            }
        }

        pub fn showModalWindowWithText(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
        ) !*w.TextArea {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = &self.modal_windows[self.modal_windows_count];
            const text_area = try window.initWithText(alloc, .{ .title = title, .max_region = self.max_modal_region });
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
            return text_area;
        }

        pub fn showModalWindowWithOptions(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
            comptime Item: type,
            context: *anyopaque,
            text_align: g.TextAlign,
        ) !*w.OptionsArea(Item) {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = &self.modal_windows[self.modal_windows_count];
            const options_area = try window.initWithOptions(
                alloc,
                Item,
                context,
                text_align,
                .{ .title = title, .max_region = self.max_modal_region },
            );
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
            return options_area;
        }

        pub fn showNotification(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
            message: []const u8,
        ) !void {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = &self.modal_windows[self.modal_windows_count];
            try window.initNotification(alloc, message, .{ .title = title, .max_region = self.max_modal_region });
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
        }

        pub fn showEntityDescription(
            self: *Self,
            alloc: std.mem.Allocator,
            session: *g.GameSession,
            entity: g.Entity,
        ) !void {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = &self.modal_windows[self.modal_windows_count];
            try window.initEntityDescription(alloc, session, entity, self.max_modal_region);
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
        }

        pub fn topModalWindow(self: *Self) ?*w.ModalWindow {
            if (self.modal_windows_count > 0) {
                return &self.modal_windows[self.modal_windows_count - 1];
            }
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
            for (0..self.modal_windows_count) |idx| {
                try self.modal_windows[idx].draw(render);
            }
        }
    };
}
