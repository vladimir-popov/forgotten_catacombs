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
const AllocatorError = std.mem.Allocator.Error;

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
        area: w.OptionsArea(g.PlayerArchetype),
        description_window: ?w.ModalWindow(w.TextArea) = null,

        /// Initializes the archetype list and restores the current selection.
        pub fn init(
            self: *Self,
            alloc: std.mem.Allocator,
            context: *Context,
        ) (AllocatorError || std.fmt.BufPrintError)!void {
            self.* = .{
                .alloc = alloc,
                .context = context,
                .area = .initEmpty(alloc, self, .center),
            };

            for (std.enums.values(g.PlayerArchetype), 0..) |arch, i| {
                _ = try self.area.addOptionFmt(
                    "{s}",
                    .{g.descriptions.Preset.castByNameAndGet(arch).name},
                    arch,
                    .do_nothing,
                );
                if (self.context.archetype == arch)
                    self.area.selectLine(i);
            }
        }

        /// Releases the options area and any open description window.
        pub fn deinit(self: *Self) void {
            self.area.deinit();
            if (self.description_window) |*win| {
                win.deinit();
            }
        }

        /// Stores the selected archetype in the shared context.
        pub fn commit(self: *Self) void {
            self.context.archetype = self.area.selectedItem().?;
            self.context.stats = g.meta.statsFromArchetype(self.context.archetype);
        }
        /// Leaves the shared context unchanged.
        pub fn rollback(_: *Self) void {}

        /// Returns buttons for the list or the nested description.
        pub fn getButtons(self: *Self) w.Buttons {
            if (self.description_window) |*win|
                return win.panel.getButtons()
            else
                return .{
                    .left = .{ .label = "Describe" },
                    .right = .{ .label = "Choose" },
                };
        }

        /// Handles archetype navigation, selection, and description display.
        pub fn handleButton(self: *Self, btn: g.Button) g.AllErrors!w.HandleButtonResult {
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
                                g.descriptions.Preset.castByNameAndGet(archetype),
                                w.FULL_SCREEN_REGION,
                            );
                        }
                    },
                    .a => {
                        return .close_window;
                    },
                    else => {},
                }
            }
            return .keep_open;
        }

        /// Draws the archetype list or its nested description.
        pub fn drawContent(self: *Self, render: g.Render) g.SystemError!void {
            try render.clearDisplay();
            if (self.description_window) |*win| {
                try win.draw(render);
            } else {
                try render.drawTextWithAlign(w.FULL_SCREEN_REGION.cols, title, .point(1, 1), .normal, .center);
                try self.area.drawContent(render, ARCHETYPE_AREA_REGION, 0);
            }
        }
    };
}
