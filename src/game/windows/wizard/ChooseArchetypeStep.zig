//! A wizard window for selecting and inspecting a character archetype.
//!
//! ```
//! ╔════════════════════════════════════════╗
//! ║         Choose your archetype:         ║
//! ║════════════════════════════════════════║
//! ║             ┌                          ║
//! ║               Adventurer               ║
//! ║              Archeologist              ║
//! ║                 Vandal                 ║
//! ║                 Rogue                  ║
//! ║                          ┘             ║
//! ║                                        ║
//! ║                                        ║
//! ║════════════════════════════════════════║
//! ║                       Describe  Choose ║
//! ╚════════════════════════════════════════╝
//! ```
const std = @import("std");
const g = @import("../../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const title = "Choose your archetype:";

const ARCHETYPE_AREA_REGION: p.Region = .{
    .top_left = .{ .row = 4, .col = 12 },
    .rows = g.DISPLAY_ROWS - 2 - 4,
    .cols = g.DISPLAY_COLS - 24,
};

/// Creates the archetype-selection step for the supplied character-building context.
pub fn ChooseArchetypeStep(comptime Context: type) type {
    return struct {
        const Self = @This();

        alloc: std.mem.Allocator,
        context: *Context,
        area: w.OptionsArea(g.meta.PlayerArchetype),
        description_window: ?w.ModalWindow(w.TextArea) = null,
        is_done: bool = false,

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.* = .{
                .alloc = alloc,
                .context = context,
                .area = .initEmpty(alloc, self, .center),
            };

            for (std.enums.values(g.meta.PlayerArchetype), 0..) |arch, i| {
                _ = try self.area.addOptionFmt(
                    "{s}",
                    .{g.components.Description.Preset.castByNameAndGet(arch).name},
                    arch,
                    .do_nothing,
                );
                if (self.context.archetype == arch)
                    self.area.selectLine(i);
            }
        }

        pub fn deinit(self: *Self) void {
            self.compositor.deinit();
            self.area.deinit();
            if (self.description_window) |*win| {
                win.deinit();
            }
        }

        pub fn isDone(self: Self) bool {
            return self.is_done;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (self.description_window) |*win| {
                if (try win.handleButton(btn) == .close_window) {
                    win.deinit();
                    self.description_window = null;
                }
            } else {
                switch (btn.game_button) {
                    .up, .down => {
                        _ = try self.area.handleButton(btn);
                    },
                    .b => {
                        std.debug.assert(self.description_window == null);
                        if (self.area.selectedItem()) |archetype| {
                            self.description_window = try w.modal_window.showDescription(
                                self.alloc,
                                g.components.Description.Preset.castByNameAndGet(archetype),
                                w.FULL_SCREEN_REGION,
                            );
                        }
                    },
                    .a => {
                        self.context.archetype = self.area.selectedItem().?;
                        self.context.stats = g.meta.statsFromArchetype(self.context.archetype);
                        self.is_done = true;
                        return .close_window;
                    },
                    else => {},
                }
            }
            return .keep_open;
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            if (self.description_window) |*win| {
                try win.draw(render);
            } else {
                try render.clearDisplay();
                try render.drawTextWithAlign(w.FULL_SCREEN_REGION.cols, title, .point(1, 1), .normal, .center);
                try self.area.draw(render, ARCHETYPE_AREA_REGION, 0);
                try render.drawLeftButton("Describe", false);
                try render.drawRightButton("Choose", false);
            }
        }
    };
}
