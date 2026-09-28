const std = @import("std");
const g = @import("../game_pkg.zig");
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
/// ║    2 points remain   Cancel  Describe  ║
/// ╚════════════════════════════════════════╝
/// ```
pub fn manageSkillsWindow(
    alloc: std.mem.Allocator,
    skills: *c.Skills,
    remaining_points: u2,
) !ManagePointsWindow("Skills", c.Skills.Skill, 0, 10) {
    return try .init(alloc, &skills.values, remaining_points);
}

pub fn ManagePointsWindow(
    comptime title: []const u8,
    Value: type,
    min_points: comptime_int, // inclusive
    max_points: comptime_int, // inclusive
) type {
    return struct {
        const AREA_REGION: p.Region = .{
            .top_left = .{ .row = 4, .col = 2 },
            .rows = g.DISPLAY_ROWS - 2 - 4,
            .cols = g.DISPLAY_COLS - 2,
        };

        const Self = @This();

        values: *std.enums.EnumArray(Value, i4),
        remaining_points: u2,
        original_points: u2,
        windows: w.WindowComposer(w.ModalWindow),

        pub fn init(
            self: *Self,
            alloc: std.mem.Allocator,
            values: *std.enums.EnumArray(Value, i4),
            remaining_points: u2,
        ) !void {
            self.* = .{
                .values = values,
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
            const options: *w.OptionsArea(Value) = self.windows.main_window.panel.area.underlying;
            for (std.enums.values(Value)) |value| {
                const option = try options.addOptionFmt(
                    "{s}",
                    .{g.components.Description.Preset.castByNameAndGet(value).name},
                    showDescription,
                );
                option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(values.get(value)));
            }
        }

        pub fn handleButton(self: *Self, btn: g.Button) !void {
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
                    _ = try self.windows.handleButton(btn);
                },
            }
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
            const area = window.initFullScreenText(description.name);
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
