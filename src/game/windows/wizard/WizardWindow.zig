const std = @import("std");
const g = @import("../../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

/// A multi-step window that initializes one union-backed step at a time.
///
/// `Steps` defines the ordered step types, while `Context` stores the result shared
/// and progressively updated by those steps.
pub fn WizardWindow(comptime Steps: type, Context: type) type {
    const steps_fields = std.meta.fields(Steps);

    return struct {
        const Self = @This();

        /// A context that should be initialized during this wizard
        context: *Context,
        /// Used to create/destroy the current step of the wizard
        step_arena: std.heap.ArenaAllocator,
        steps: Steps = undefined,
        current_step: usize = 0,

        /// Initializes the first step and stores the shared wizard context.
        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.* = .{
                .step_arena = .init(alloc),
                .context = context,
            };
            try self.switchToStep(0);
        }

        /// Releases the arena containing the current step.
        pub fn deinit(self: *Self) void {
            self.step_arena.deinit();
        }

        /// Handles the current step and performs forward/backward navigation.
        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            const current_step = self.current_step;
            inline for (0..steps_fields.len) |idx| {
                // handle the button by the current step
                if (current_step == idx) {
                    const field = steps_fields[idx];
                    // switch back
                    if (btn.game_button == .b and idx > 0) {
                        try @field(self.steps, field.name).rollback();
                        try self.switchToStep(idx - 1);
                    } else
                    // switch to the next step
                    if (try @field(self.steps, field.name).handleButton(btn) == .close_window) {
                        if (btn.game_button == .a) {
                            if (idx + 1 < steps_fields.len) {
                                // commit changes and switch to the next step
                                try @field(self.steps, field.name).commit();
                                try self.switchToStep(idx + 1);
                            } else {
                                return .close_window;
                            }
                        }
                    }
                }
            }
            return .keep_open;
        }

        /// Commits or rolls back the current step storage and initializes `idx`.
        pub fn switchToStep(self: *Self, comptime idx: comptime_int) !void {
            std.debug.assert(self.step_arena.reset(.retain_capacity));
            const field = steps_fields[idx];
            self.steps = @unionInit(Steps, field.name, undefined);
            self.current_step = idx;
            try @field(self.steps, field.name).init(self.step_arena.allocator(), self.context);
        }

        /// Draws the current step and its navigation buttons.
        pub fn draw(self: *Self, render: g.Render) !void {
            try render.clearDisplay();

            var buttons: w.Buttons = undefined;
            // Draw the current step and gets its buttons:
            inline for (0..steps_fields.len) |idx| {
                if (self.current_step == idx) {
                    const field = steps_fields[idx];
                    try @field(self.steps, field.name).drawContent(render);
                    buttons = @field(self.steps, field.name).getButtons();
                }
            }

            if (buttons.left) |btn|
                try render.drawLeftButton(btn.label, btn.has_alternative)
            else if (self.current_step > 0)
                try render.drawLeftButton("Back", false)
            else
                try render.hideLeftButton();

            if (buttons.right) |btn|
                try render.drawRightButton(btn.label, btn.has_alternative)
            else if (self.current_step + 1 < steps_fields.len)
                try render.drawRightButton("Next", false)
            else if (self.current_step + 1 == steps_fields.len)
                try render.drawRightButton("Done", false)
            else
                try render.hideRightButton();
        }
    };
}
