const std = @import("std");
const g = @import("../../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

/// ```
/// ╔════════════════════════════════════════╗
/// ║                 Skill:                 ║
/// ║════════════════════════════════════════║
/// ║ ┌                                      ║
/// ║  Weapon Mastery                      0 ║
/// ║  Mechanics                           0 ║
/// ║  Stealth                             0 ║
/// ║  Echo of knowledge                   0 ║
/// ║                                       ┘║
/// ║                                        ║
/// ║                                        ║
/// ║════════════════════════════════════════║
/// ║    2 points remain           Describe  ║
/// ╚════════════════════════════════════════╝
/// ```
pub fn ManageSkillsStep(comptime Context: type) type {
    return ManagePointsStep("Skills:", Context, c.Skills.Skill, "skills", 0, 10);
}

pub fn ManageStatsStep(comptime Context: type) type {
    return ManagePointsStep("Stats:", Context, c.Stats.Stat, "stats", -2, 5);
}

fn ManagePointsStep(
    comptime title: []const u8,
    Context: type,
    Value: type,
    comptime field_name: []const u8,
    min_points: comptime_int, // inclusive
    max_points: comptime_int, // inclusive
) type {
    std.debug.assert(@hasField(Context, field_name));

    return struct {
        const AREA_REGION: p.Region = .{
            .top_left = .{ .row = 4, .col = 2 },
            .rows = g.DISPLAY_ROWS - 2 - 4,
            .cols = g.DISPLAY_COLS - 2,
        };

        const Self = @This();

        alloc: std.mem.Allocator,
        values: *std.enums.EnumArray(Value, i4),
        remaining_points: u2,
        original_points: u2,
        windows: w.WindowComposer(w.ModalWindow),

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            const remaining_points: u2 = @field(context, field_name ++ "RemainingPoints")(context);
            self.* = .{
                .alloc = alloc,
                .values = &@field(context, field_name).values,
                .remaining_points = remaining_points,
                .original_points = remaining_points,
                .windows = .init(
                    .initOptions(
                        alloc,
                        Value,
                        self,
                        .left,
                        .{ .title = title, .max_region = w.ModalWindow.DEFAULT_MAX_REGION },
                    ),
                    w.ModalWindow.DEFAULT_MAX_REGION,
                ),
            };
            const options: *w.OptionsArea(Value) = @ptrCast(@alignCast(self.windows.main_window.panel.area.underlying));
            for (std.enums.values(Value)) |value| {
                const option = try options.addOptionFmt(
                    "{s}",
                    .{g.components.Description.Preset.castByNameAndGet(value).name},
                    showDescription,
                );
                option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(self.values.get(value)));
            }
        }

        pub fn deinit(self: *Self) void {
            self.windows.deinit();
        }

        pub fn isDone(self: Self) bool {
            return self.remaining_points == 0;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            switch (btn.game_button) {
                .left, .right => if (self.windows.modal_windows_count == 0) {
                    const option = self.windows.main_window.selectedOption().?;
                    if (btn.game_button == .right)
                        self.increase(option.item)
                    else
                        self.decrise(option.item);

                    const new_value = self.values.get(option.item);
                    option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(new_value));
                },
                else => {
                    return try self.windows.handleButton(btn);
                },
            }
            return .keep_open;
        }

        fn selectedValue(self: Self) Value {
            return self.options.selectedItem().?;
        }

        fn increase(self: *Self, value: Value) void {
            if (self.remaining_points > 0 and self.values.get(value) < max_points) {
                const new_value = self.values.get(value) + 1;
                self.values.set(value, new_value);
                self.remaining_points -= 1;
            }
        }

        fn decrise(self: *Self, value: Value) void {
            if (self.remaining_points < self.original_points and self.values.get(value) > min_points) {
                const new_value = self.values.get(value) - 1;
                self.values.set(value, new_value);
                self.remaining_points += 1;
            }
        }

        fn showDescription(
            ptr: *anyopaque,
            _: usize,
            value: Value,
        ) anyerror!w.HandleButtonResult {
            const self: *Self = @ptrCast(@alignCast(ptr));
            const description = g.components.Description.Preset.castByNameAndGet(value);
            const window = try self.windows.newModalWindow();
            const area = window.initFullScreenText(self.alloc, description.name);
            for (description.description) |descr_line| {
                try area.printLineFmt("{s}", .{descr_line});
            }
        }

        pub fn draw(self: Self, render: g.Render) !void {
            try self.windows.draw(render);
            var buf: [15]u8 = undefined;
            try render.drawInfo(
                try std.fmt.bufPrint(&buf, "{d} points remain", .{self.remaining_points}),
            );
            if (self.remaining_points > 0)
                try render.drawRightButton("Describe", false);
        }
    };
}
