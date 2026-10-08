//! Composes a borrowed main window with a stack of owned modal windows.
//!
//! The compositor does not own `main_window`: the caller must keep it alive for
//! the compositor's entire lifetime and remains responsible for deinitializing
//! it. The main window must implement the following interface:
//!
//! ```zig
//! pub fn handleButton(self: *MainWindow, btn: g.Button) !w.HandleButtonResult
//! pub fn draw(self: *MainWindow, render: g.Render) !void
//! ```
//!
//! Modal windows are different: after a `show*` function succeeds, ownership of
//! the new modal window belongs to the compositor. A pointer returned by a
//! `show*` function is borrowed and remains valid only until that modal window
//! is closed or the compositor is deinitialized. The caller must not invoke
//! `deinit` on a modal window owned by the compositor.
//!
//! Input is sent exclusively to the topmost modal window while one exists.
//! When that window returns `.close_window`, the compositor deinitializes it
//! and removes it from the stack. With no modal windows, input is forwarded to
//! the borrowed main window. Drawing proceeds in the opposite direction: the
//! main window is drawn first, followed by modal windows from bottom to top.
//!
//! `deinit` releases compositor-owned modal resources, but deliberately does
//! not deinitialize the borrowed main window. A typical owner therefore tears
//! the objects down in this order:
//!
//! ```zig
//! compositor.deinit();
//! main_window.deinit();
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

/// Describes whether input closed the main window, a modal window, or neither.
pub const ClosedWindow = enum { closed_main_window, closed_modal_window, keep_window };

const GenericWindow = struct {
    const VTable = struct {
        handleButtonFn: *const fn (underlying: *anyopaque, btn: g.Button) anyerror!w.HandleButtonResult,
        drawFn: *const fn (underlying: *anyopaque, render: g.Render) anyerror!void,
        deinitFn: *const fn (underlying: *anyopaque) void,
    };

    ptr: *anyopaque,
    vtable: VTable,

    /// Creates a non-owning type-erased reference to `window`.
    pub fn wrap(comptime W: type, window: *W) GenericWindow {
        return .{
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
    }

    pub fn handleButton(self: *@This(), btn: g.Button) !w.HandleButtonResult {
        return try self.vtable.handleButtonFn(self.ptr, btn);
    }

    pub fn draw(self: *@This(), render: g.Render) !void {
        try self.vtable.drawFn(self.ptr, render);
    }

    pub fn deinit(self: @This()) void {
        self.vtable.deinitFn(self.ptr);
    }
};

const GenericModalWindow = struct {
    arena: *std.heap.ArenaAllocator,
    underlying: ?GenericWindow,

    /// Creates an empty reusable slot for a single modal window.
    pub fn init(alloc: std.mem.Allocator) !GenericModalWindow {
        const self = GenericModalWindow{ .arena = try alloc.create(std.heap.ArenaAllocator), .underlying = null };
        self.arena.* = .init(alloc);
        return self;
    }

    /// Releases the storage owned by this modal slot.
    pub fn deinit(self: *@This()) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    /// Replaces the slot's current window and stores `prototype_window` in the
    /// slot arena. On success, the returned pointer is borrowed from the slot.
    pub fn wrap(self: *@This(), prototype_window: anytype) !*@TypeOf(prototype_window) {
        const W = @TypeOf(prototype_window);
        self.unwrap();
        const window = try self.arena.allocator().create(W);
        window.* = prototype_window;
        self.underlying = .wrap(W, window);
        return window;
    }

    /// Deinitializes the contained window, empties the slot, and retains the
    /// arena capacity for reuse.
    pub fn unwrap(self: *@This()) void {
        if (self.underlying) |*underlying| {
            underlying.deinit();
        }
        self.underlying = null;
        std.debug.assert(self.arena.reset(.retain_capacity));
    }
};

const Self = @This();

main_window: GenericWindow,
modal_windows: [3]GenericModalWindow,
max_modal_region: p.Region = w.FULL_SCREEN_REGION,
modal_windows_count: usize = 0,
is_redrawing_required: bool = true,

/// Creates a compositor borrowing `main_window`.
///
/// `main_window` must be a pointer to an object implementing the window
/// interface documented at the top of this file. The pointed-to object must
/// outlive the returned compositor and must remain at a stable address.
///
/// `alloc` is used for the compositor's reusable modal slots. Allocators passed
/// later to `show*` functions are used by the concrete modal window contents.
/// `max_modal_region` constrains modal windows created by the compositor.
pub fn init(alloc: std.mem.Allocator, main_window: anytype, max_modal_region: p.Region) !Self {
    const MW = @TypeOf(main_window);
    const pointer_type_info = @typeInfo(MW).pointer;
    return .{
        .main_window = .wrap(pointer_type_info.child, main_window),
        .modal_windows = .{
            try .init(alloc),
            try .init(alloc),
            try .init(alloc),
        },
        .max_modal_region = max_modal_region,
    };
}

/// Releases all modal windows owned by the compositor.
///
/// Does not deinitialize `main_window`; it is borrowed from the caller. All
/// pointers previously returned by `show*` functions become invalid.
pub fn deinit(self: *Self) void {
    for (0..self.modal_windows_count) |idx| {
        self.modal_windows[idx].deinit();
    }
}

/// Creates and pushes a modal window containing an initially empty text area.
///
/// On success, the compositor owns the window. The returned pointer is
/// borrowed and may be used to populate or otherwise mutate the live modal
/// window. It remains valid until the window is closed or the compositor is
/// deinitialized; the caller must not deinitialize it.
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

/// Creates and pushes a modal window containing typed selectable options.
///
/// `context` is borrowed by the options area and must remain valid for the
/// lifetime of the modal window. On success, the compositor owns the window;
/// the returned pointer is borrowed until the window closes or the compositor
/// is deinitialized.
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

/// Creates and pushes a fully populated notification window.
///
/// On success, the compositor owns the notification and deinitializes it when
/// it closes or when the compositor itself is deinitialized.
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

/// Creates and pushes a modal description of `entity`.
///
/// `session` is borrowed by callbacks installed in the modal window and must
/// remain valid until the window closes. On success, the compositor owns the
/// window and is responsible for deinitializing it.
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

/// Returns the concrete area of the topmost modal window, if one exists.
///
/// `Area` must exactly match the concrete area type stored in the topmost
/// modal window. Passing the wrong type violates this function's contract. The
/// returned pointer is borrowed and becomes invalid when that window closes.
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

/// Sends input to the topmost modal window, or to the main window when there
/// are no modals.
///
/// A modal that requests closing is deinitialized and removed before this
/// function returns `.closed_modal_window`. Closing the borrowed main window
/// is only reported; its owner remains responsible for deinitializing it.
pub fn handleButton(self: *Self, btn: g.Button) !ClosedWindow {
    self.is_redrawing_required = true;
    if (self.modal_windows_count > 0) {
        const current_idx = self.modal_windows_count - 1;
        const window = &self.modal_windows[current_idx];
        if (window.underlying) |*underlying_window| {
            if (try underlying_window.handleButton(btn) == .close_window) {
                window.unwrap();
                var idx = current_idx;
                while (idx + 1 < self.modal_windows_count) : (idx += 1) {
                    std.mem.swap(
                        GenericModalWindow,
                        &self.modal_windows[idx],
                        &self.modal_windows[idx + 1],
                    );
                }
                self.modal_windows_count -= 1;
                return .closed_modal_window;
            }
        }
    } else if (try self.main_window.handleButton(btn) == .close_window) {
        return .closed_main_window;
    }
    return .keep_window;
}

/// Draws the borrowed main window followed by owned modal windows from bottom
/// to top. Does nothing when no redraw has been requested.
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
