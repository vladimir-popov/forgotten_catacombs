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
    std.debug.assert(@hasField(Context, "archetype"));
    return struct {
        const Self = @This();

        windows: w.WindowComposer(w.ModalWindow),
        context: *Context,

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.context = context;
            try self.windows.init(.initOptions(
                alloc,
                g.meta.PlayerArchetype,
                self,
                .center,
                .{ .title = "Choose your archetype:", .max_region = w.ModalWindow.DEFAULT_MAX_REGION },
            ), w.ModalWindow.DEFAULT_MAX_REGION);

            const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                @ptrCast(@alignCast(self.windows.main_window.panel.area.underlying));

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
            self.windows.deinit();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (self.windows.modal_windows_count == 0) {
                switch (btn.game_button) {
                    .a => {
                        const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                            @ptrCast(@alignCast(self.windows.main_window.panel.area.underlying));
                        self.context.archetype = options.selectedItem().?;
                        return .close_window;
                    },
                    .b => {
                        const options: *w.OptionsArea(g.meta.PlayerArchetype) =
                            @ptrCast(@alignCast(self.windows.main_window.panel.area.underlying));
                        const value = options.selectedItem().?;
                        const description = g.components.Description.Preset.castByNameAndGet(value);
                        const window = try self.windows.newModalWindow();
                        const area = window.initFullScreenText(self.alloc, description.name);
                        for (description.description) |descr_line| {
                            try area.printLineFmt("{s}", .{descr_line});
                        }
                    },
                    else => {},
                }
            } else {
                return try self.windows.handleButton(btn);
            }
            return .keep_open;
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            try self.windows.draw(render);
            try render.drawLeftButton("Describe", false);
            try render.drawRightButton("Choose", false);
        }
    };
}
