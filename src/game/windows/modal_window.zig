const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const w = g.windows;

pub const Params = struct {
    title: []const u8 = &.{},
    max_region: p.Region = w.FULL_SCREEN_REGION,
};

pub fn withText(alloc: std.mem.Allocator, params: Params) !ModalWindow(w.TextArea) {
    var self = ModalWindow(w.TextArea){
        .region = params.max_region,
        .panel = .{
            .area = w.TextArea.initEmpty(alloc),
            .region = params.max_region.innerRegion(1, 1, 1, 1),
        },
    };
    try self.formatTitle("{s}", .{params.title});
    return self;
}

pub fn fullScreenText(alloc: std.mem.Allocator, window_title: []const u8) !ModalWindow(w.TextArea) {
    return try .initWithText(alloc, .{ .title = window_title, .max_region = w.FULL_SCREEN_REGION });
}

/// Example:
/// ```
/// ┌──────────────Title───────────────┐
/// │              Option              │
/// │░░░░░░░░░░░░░ Option ░░░░░░░░░░░░░│
/// │              Option              │
/// └──────────────────────────────────┘
///═══════════════════════════════════════
///                          Close Choose
/// ```
pub fn withOptions(
    alloc: std.mem.Allocator,
    comptime Item: type,
    context: *anyopaque,
    text_align: g.TextAlign,
    params: Params,
) !ModalWindow(w.OptionsArea(Item)) {
    var self = ModalWindow(w.OptionsArea(Item)){
        .region = params.max_region,
        .panel = .{
            .area = w.OptionsArea(Item).initEmpty(alloc, context, text_align),
            .region = params.max_region.innerRegion(1, 1, 1, 1),
        },
    };
    try self.formatTitle("{s}", .{params.title});
    return self;
}

/// Shows a multiline message in the modal window.
/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │               Multi               │
/// │               line                │
/// │              message              │
/// └───────────────────────────────────┘
/// ```
pub fn notification(
    alloc: std.mem.Allocator,
    message: []const u8,
    params: Params,
) !ModalWindow(w.TextArea) {
    var self = try withText(alloc, params);
    var itr = std.mem.splitScalar(u8, message, '\n');
    while (itr.next()) |msg_line| {
        const line = try self.panel.area.addEmptyLine();
        const width = g.DISPLAY_COLS - 2;
        const pad = p.diff(msg_line.len, width) / 2;
        _ = try std.fmt.bufPrint(line[pad..], "{s}", .{msg_line});
    }
    self.shrinkToContent();
    return self;
}

/// Approximate example:
/// ```
/// ┌───────────────Club────────────────┐
/// │A gnarled piece of wood, scarred   │
/// │from use. Deals blunt damage.      │
/// │Cheap and easy to use.             │
/// │                                   │
/// │Damage: cutting 2-3                │
/// │Weight: 3                          │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn entityDescription(
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    entity: g.Entity,
    max_region: p.Region,
) !ModalWindow(w.TextArea) {
    var self = try withText(alloc, .{ .max_region = max_region });
    try self.formatTitle("{f}", .{g.Description.actualNameFormatter(session.journal, entity)});
    const text_area = &self.panel.area;
    if (session.player.id == entity.id) {
        text_area.b_button = .{ .button = .up_level, .context = session, .handler = struct {
            fn upLevel(ptr: *anyopaque) !w.HandleButtonResult {
                const ss: *g.GameSession = @ptrCast(@alignCast(ptr));
                try ss.levelUp();
                return .close_window;
            }
        }.upLevel };
        try g.Description.describePlayer(session.journal, entity, text_area);
    } else if (session.registry.has(entity, g.components.EnemyState)) {
        try g.Description.describeEnemy(session.journal, entity, text_area);
    } else {
        const is_equipped = g.meta.isEquipped(&session.registry, session.player, entity);
        try g.Description.describeItem(session.journal, entity, is_equipped, text_area);
    }
    return self;
}

pub fn ModalWindow(comptime Area: type) type {
    return struct {
        const Self = @This();

        title_buffer: [32]u8 = undefined,
        title_len: usize = 0,
        panel: w.ScrollablePanel(Area),
        region: p.Region,

        pub fn deinit(self: *Self) void {
            self.panel.area.deinit();
        }

        // this method must be either inline or receive a pointer to the self
        pub fn title(self: *const Self) []const u8 {
            return self.title_buffer[0..self.title_len];
        }

        pub fn formatTitle(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            self.title_len = (try std.fmt.bufPrint(&self.title_buffer, fmt, args)).len;
        }

        /// Shrinks the window vertically to fit its content.
        ///
        /// The resulting height includes the top and bottom borders and is limited by
        /// the current window region. If the content is shorter than the available
        /// height, the window is vertically centered within that region.
        ///
        /// Updates the scrollable area's region to match the resized window.
        pub fn shrinkToContent(self: *Self) void {
            // Count of rows that should be drawn (including border)
            const rows: usize = self.panel.totalLines() + 2; // 2 for border
            const max_region = self.region;
            self.region = .{
                .top_left = if (rows < max_region.rows)
                    max_region.top_left.movedToNTimes(.down, (max_region.rows - rows) / 2)
                else
                    max_region.top_left,
                .rows = @min(rows, max_region.rows),
                .cols = max_region.cols,
            };
            self.panel.region = self.region.innerRegion(1, 1, 1, 1);
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            return try self.panel.handleButton(btn);
        }

        /// Draws the window with a scrollbar and buttons if they are required.
        pub fn draw(self: *Self, render: g.Render) !void {
            try self.drawContent(render);
            try self.drawBorder(render);
            try self.drawTitle(render);
            try self.drawButtons(render);
        }

        /// Draws the title
        fn drawTitle(self: *const Self, render: g.Render) !void {
            const padding: u8 = @intCast(self.region.cols - self.title_len);
            const point = self.region.top_left.movedToNTimes(.right, padding / 2);
            const ttl = self.title();
            try render.drawText(ttl, point, .normal);
        }

        /// Draws the content of its inner scrollable panel
        pub fn drawContent(self: *const Self, render: g.Render) !void {
            try self.panel.draw(render);
        }

        /// Draws the border around its region
        fn drawBorder(self: *const Self, render: g.Render) !void {
            try render.drawBorder(self.region);
        }

        /// Draws the border around its region
        pub fn drawButtons(self: *const Self, render: g.Render) !void {
            if (self.panel.leftButton()) |btn| {
                try render.drawLeftButton(btn.text, btn.has_alternatives);
            } else {
                try render.hideLeftButton();
            }
            if (self.panel.rightButton()) |btn| {
                try render.drawRightButton(btn.text, btn.has_alternatives);
            } else {
                try render.hideRightButton();
            }
        }

        /// Fills the region of the window either from the buffer, or just fill it with spaces.
        pub fn hide(self: *Self, render: g.Render, hide_mode: w.HideMode) !void {
            switch (hide_mode) {
                .from_buffer => try render.redrawRegionFromSceneBuffer(self.region),
                .fill_region => try render.fillRegion(g.Render.default_filler, .normal, self.region),
            }
        }
    };
}
