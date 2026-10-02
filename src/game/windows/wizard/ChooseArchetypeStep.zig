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

pub fn ChooseArchetypeStep(comptime Context: type) type {
    return struct {
        const Self = @This();

        const MainWindow = w.ModalWindow(w.OptionsArea(g.meta.PlayerArchetype));

        alloc: std.mem.Allocator,
        main_window: MainWindow,
        compositor: w.WindowCompositor(MainWindow),
        context: *Context,

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.alloc = alloc;
            self.context = context;
            self.main_window = try w.modal_window.withOptions(
                alloc,
                g.meta.PlayerArchetype,
                self,
                .center,
                .{ .title = "Choose your archetype:", .max_region = w.FULL_SCREEN_REGION },
            );

            const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                &self.main_window.panel.area;

            for (std.enums.values(g.meta.PlayerArchetype)) |arch| {
                const option = try options.addEmptyOption(arch);
                option.label_len = (try std.fmt.bufPrint(
                    &option.label_buffer,
                    "{s}",
                    .{g.components.Description.Preset.castByNameAndGet(arch).name},
                )).len;
            }
        }

        pub fn deinit(self: *Self) void {
            self.compositor.deinit();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (self.compositor.modal_windows_count == 0) {
                switch (btn.game_button) {
                    .a => {
                        const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                            &self.main_window.panel.area;
                        self.context.archetype = options.selectedItem().?;
                        return .close_window;
                    },
                    .b => {
                        const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                            &self.main_window.panel.area;
                        const value = options.selectedItem().?;
                        const description = g.components.Description.Preset.castByNameAndGet(value);
                        const window = try self.compositor.showModalWindowWithText(self.alloc, description.name);
                        const area = &window.panel.area;
                        for (description.description) |descr_line| {
                            try area.printLineFmt("{s}", .{descr_line});
                        }
                    },
                    else => {},
                }
            } else {
                return try self.compositor.handleButton(btn);
            }
            return .keep_open;
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            try self.main_window.draw(render);
            try render.drawLeftButton("Describe", false);
            try render.drawRightButton("Choose", false);
        }
    };
}
