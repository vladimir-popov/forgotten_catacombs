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
pub fn WindowCompositor(comptime MainWindow: type) type {
    const GenericModalWindow = struct {
        const VTable = struct {
            handleButtonFn: *const fn (underlying: *anyopaque, btn: g.Button) anyerror!w.HandleButtonResult,
            drawFn: *const fn (underlying: *anyopaque, render: g.Render) anyerror!void,
            deinitFn: *const fn (underlying: *anyopaque) void,
        };

        const Self = @This();

        arena: std.heap.ArenaAllocator,
        underlying: ?struct {
            ptr: *anyopaque,
            vtable: VTable,

            pub fn handleButton(self: *@This(), btn: g.Button) !w.HandleButtonResult {
                return try self.vtable.handleButtonFn(self.ptr, btn);
            }

            pub fn draw(self: *@This(), render: g.Render) !void {
                try self.vtable.drawFn(self.ptr, render);
            }

            pub fn deinit(self: @This()) void {
                self.vtable.deinitFn(self.ptr);
            }
        },

        pub fn init(alloc: std.mem.Allocator) Self {
            return .{ .arena = .init(alloc), .underlying = null };
        }

        pub fn deinit(self: *Self) void {
            self.arena.deinit();
        }

        pub fn wrap(self: *Self, prototype_window: anytype) !*@TypeOf(prototype_window) {
            const W = @TypeOf(prototype_window);
            self.unwrap();
            const window = try self.arena.allocator().create(W);
            window.* = prototype_window;
            self.underlying = .{
                .ptr = @ptrCast(window),
                .vtable = struct {
                    fn handleButtonFn(ptr: *anyopaque, btn: g.Button) !w.HandleButtonResult {
                        const win: *W = @ptrCast(@alignCast(ptr));
                        return try win.handleButton(btn);
                    }
                    fn drawFn(ptr: *anyopaque, render: g.Render) !void {
                        const win: *W = @ptrCast(@alignCast(ptr));
                        try win.draw(render);
                    }
                    fn deinitFn(ptr: *anyopaque) void {
                        const win: *W = @ptrCast(@alignCast(ptr));
                        win.deinit();
                    }
                    const vtable: VTable = .{
                        .handleButtonFn = handleButtonFn,
                        .drawFn = drawFn,
                        .deinitFn = deinitFn,
                    };
                }.vtable,
            };
            return window;
        }

        pub fn unwrap(self: *Self) void {
            if (self.underlying) |*underlying| {
                underlying.deinit();
            }
            std.debug.assert(self.arena.reset(.retain_capacity));
        }
    };

    return struct {
        const Self = @This();

        main_window: *MainWindow,
        modal_windows: [3]GenericModalWindow,
        max_modal_region: p.Region = w.FULL_SCREEN_REGION,
        modal_windows_count: usize = 0,
        is_redrawing_required: bool = true,

        pub fn init(alloc: std.mem.Allocator, main_window: *MainWindow, max_modal_region: p.Region) Self {
            return .{
                .main_window = main_window,
                .modal_windows = .{
                    .init(alloc),
                    .init(alloc),
                    .init(alloc),
                },
                .max_modal_region = max_modal_region,
            };
        }

        /// Releases all modal windows owned by the compositor.
        ///
        /// Does not deinitialize `main_window`; it is borrowed from the caller.
        pub fn deinit(self: *Self) void {
            for (0..self.modal_windows_count) |idx| {
                self.modal_windows[idx].deinit();
            }
        }

        pub fn showModalWindowWithText(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
        ) !*w.ModalWindow(w.TextArea) {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = try self.modal_windows[self.modal_windows_count].wrap(
                try w.modal_window.withText(alloc, .{ .title = title, .max_region = self.max_modal_region }),
            );
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
            return window;
        }

        pub fn showModalWindowWithOptions(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
            comptime Item: type,
            context: *anyopaque,
            text_align: g.TextAlign,
        ) !*w.ModalWindow(w.OptionsArea(Item)) {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            const window = try self.modal_windows[self.modal_windows_count].wrap(try w.modal_window.withOptions(
                alloc,
                Item,
                context,
                text_align,
                .{ .title = title, .max_region = self.max_modal_region },
            ));
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
            return window;
        }

        pub fn showNotification(
            self: *Self,
            alloc: std.mem.Allocator,
            title: []const u8,
            message: []const u8,
        ) !void {
            std.debug.assert(self.modal_windows_count < self.modal_windows.len);
            _ = try self.modal_windows[self.modal_windows_count].wrap(
                try w.modal_window.notification(alloc, message, .{ .title = title, .max_region = self.max_modal_region }),
            );
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
            _ = try self.modal_windows[self.modal_windows_count].wrap(
                try w.modal_window.entityDescription(alloc, session, entity, w.FULL_SCREEN_REGION),
            );
            self.modal_windows_count += 1;
            self.is_redrawing_required = true;
        }

        pub fn topModalWindowArea(self: *Self, comptime Area: type) ?*Area {
            if (self.topModalWindow()) |generic_window| {
                if (generic_window.underlying) |underlying| {
                    const window: *w.ModalWindow(Area) = @ptrCast(@alignCast(underlying.ptr));
                    return &window.panel.area;
                }
            }
            return null;
        }

        fn topModalWindow(self: *Self) ?*GenericModalWindow {
            if (self.modal_windows_count > 0) {
                return &self.modal_windows[self.modal_windows_count - 1];
            }
            return null;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            self.is_redrawing_required = true;
            if (self.modal_windows_count > 0) {
                const window = &self.modal_windows[self.modal_windows_count - 1];
                if (window.underlying) |*underlying_window| {
                    if (try underlying_window.handleButton(btn) == .close_window) {
                        window.unwrap();
                        self.modal_windows_count -= 1;
                    }
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
                if (self.modal_windows[idx].underlying) |*underlying_window| {
                    try underlying_window.draw(render);
                }
            }
        }
    };
}
