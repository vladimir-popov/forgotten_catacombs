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

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            self.* = .{
                .step_arena = .init(alloc),
                .context = context,
            };
            try self.switchToStep(0);
        }

        pub fn deinit(self: *Self) void {
            self.step_arena.deinit();
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            const current_step = self.current_step;
            inline for (0..steps_fields.len) |idx| {
                if (current_step == idx) {
                    const field = steps_fields[idx];
                    if (btn.game_button == .b and idx > 0) {
                        try self.switchToStep(idx - 1);
                    } else if (try @field(self.steps, field.name).handleButton(btn) == .close_window) {
                        if (btn.game_button == .a) {
                            if (idx + 1 < steps_fields.len)
                                try self.switchToStep(idx + 1)
                            else
                                return .close_window;
                        }
                    }
                }
            }
            return .keep_open;
        }

        pub fn switchToStep(self: *Self, comptime idx: comptime_int) !void {
            std.debug.assert(self.step_arena.reset(.retain_capacity));
            const field = steps_fields[idx];
            self.steps = @unionInit(Steps, field.name, undefined);
            self.current_step = idx;
            try @field(self.steps, field.name).init(self.step_arena.allocator(), self.context);
        }

        pub fn draw(self: *Self, render: g.Render) !void {
            try render.cleanInfo();

            var is_step_completed = false;
            inline for (0..steps_fields.len) |idx| {
                if (self.current_step == idx) {
                    const field = steps_fields[idx];
                    try @field(self.steps, field.name).draw(render);
                    is_step_completed = @field(self.steps, field.name).isDone();
                }
            }

            if (self.current_step > 0)
                try render.drawLeftButton("Back", false);

            if (self.current_step + 1 < steps_fields.len and is_step_completed)
                try render.drawRightButton("Next", false);
        }
    };
}
