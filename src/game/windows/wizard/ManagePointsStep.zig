const std = @import("std");
const g = @import("../../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

/// Creates a wizard window for distributing points between character skills.
///
/// ```
/// ╔════════════════════════════════════════╗
/// ║      Distribute the skill points:      ║
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
    return ManagePointsStep("Distribute the skill points:", Context, c.Skills.Skill, "skills", 0, 10);
}

/// Creates a wizard window for distributing points between character stats.
pub fn ManageStatsStep(comptime Context: type) type {
    return ManagePointsStep("Distribute the stats points:", Context, c.Stats.Stat, "stats", -2, 5);
}

fn ManagePointsStep(
    comptime title: []const u8,
    Context: type,
    Value: type,
    comptime field_name: []const u8,
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

        alloc: std.mem.Allocator,
        values: *std.enums.EnumArray(Value, i4),
        remaining_points: u4,
        original_points: u4,
        area: w.OptionsArea(Value),
        description_window: ?w.ModalWindow(w.TextArea),

        pub fn init(self: *Self, alloc: std.mem.Allocator, context: *Context) !void {
            const remaining_points: u4 = @field(Context, field_name ++ "RemainingPoints")(context);
            self.* = .{
                .alloc = alloc,
                .values = &@field(context, field_name).values,
                .remaining_points = remaining_points,
                .original_points = remaining_points,
                .area = .initEmpty(alloc, self, .left),
                .description_window = null,
            };

            for (std.enums.values(Value)) |value| {
                const fmt = std.fmt.comptimePrint("{{s: <{d}}}", .{AREA_REGION.cols});
                const option = try self.area.addOptionFmt(
                    fmt,
                    .{g.components.Description.Preset.castByNameAndGet(value).name},
                    value,
                    .{ .handle_release_button = showDescription },
                );
                const x = self.values.get(value);
                if (x < 0) {
                    option.label_buffer[option.label_len - 4] = '-';
                }
                option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(@abs(x)));
            }
        }

        pub fn deinit(self: *Self) void {
            self.area.deinit();
            if (self.description_window) |*win| {
                win.deinit();
            }
        }

        pub fn isDone(self: Self) bool {
            return self.remaining_points == 0;
        }

        pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
            if (self.description_window) |*win| {
                if (try win.handleButton(btn) == .close_window) {
                    win.deinit();
                    self.description_window = null;
                }
            } else {
                switch (btn.game_button) {
                    .left, .right => {
                        const option = self.area.selectedOption().?;
                        if (btn.game_button == .right)
                            self.increase(option.item)
                        else
                            self.decrise(option.item);

                        const x = self.values.get(option.item);
                        if (x < 0) {
                            option.label_buffer[option.label_len - 4] = '-';
                        } else {
                            option.label_buffer[option.label_len - 4] = ' ';
                        }
                        option.label_buffer[option.label_len - 3] = '0' + @as(u8, @intCast(@abs(x)));
                    },
                    .up, .down => _ = try self.area.handleButton(btn),
                    .a => if (self.remaining_points > 0) {
                        return try self.area.handleButton(btn);
                    } else {
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
                try self.area.draw(render, AREA_REGION, 0);
                var buf: [15]u8 = undefined;
                try render.drawInfo(
                    try std.fmt.bufPrint(&buf, "{d} points remain", .{self.remaining_points}),
                );
                if (self.remaining_points > 0)
                    try render.drawRightButton("Describe", false);
            }
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
            std.debug.assert(self.description_window == null);
            self.description_window = try w.modal_window.showDescription(
                self.alloc,
                g.components.Description.Preset.castByNameAndGet(value),
                w.FULL_SCREEN_REGION,
            );
            return .keep_open;
        }
    };
}
