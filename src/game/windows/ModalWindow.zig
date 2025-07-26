const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const Self = @This();

const COLS = w.TextArea.COLS;

const Line = w.TextArea.Line;

title: []const u8,
text_area: w.TextArea,
right_button_label: []const u8 = "Close",

pub fn deinit(self: *Self, alloc: std.mem.Allocator) void {
    self.text_area.deinit(alloc);
}

/// Example:
/// ```
/// ┌───────────────Title───────────────┐
/// │              Message              │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn initNotification(alloc: std.mem.Allocator, title: []const u8, message: []const u8) !Self {
    var text_area = w.TextArea.init(.modal);
    try text_area.addLine(alloc, message, false);
    return .{ .title = title, .text_area = text_area };
}

/// Example:
/// ```
/// ┌────────────────Club───────────────┐
/// │ Id: 12                            │
/// │ Damage: 2-5                       │
/// └───────────────────────────────────┘
///═══════════════════════════════════════
///                                Close
/// ```
pub fn initEntityDescription(
    alloc: std.mem.Allocator,
    registry: g.Registry,
    entity: g.Entity,
    dev_mode: bool,
) !Self {
    var title: []const u8 = "";
    var text_area = w.TextArea.init(.modal);
    if (registry.get(entity, c.Description)) |description| {
        title = description.name();
        for (description.description()) |str| {
            const line = try text_area.addEmptyLine(alloc, false);
            std.mem.copyForwards(u8, line, str);
        }
        if (description.description().len > 0) {
            const line = try text_area.lines.addOne(alloc);
            line.* = @splat('-');
        }
    }
    if (dev_mode) {
        var line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Id: {d}", .{entity.id});
        if (registry.get(entity, c.Position)) |position| {
            line = try text_area.addEmptyLine(alloc, false);
            _ = try std.fmt.bufPrint(line[1..], "Position: {any}", .{position.place});
        }
    }
    if (registry.get(entity, c.EnemyState)) |state| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "State: is {s}", .{@tagName(state.*)});
    }
    if (registry.get(entity, c.Health)) |health| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
    }
    if (registry.get(entity, c.Speed)) |speed| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
    }
    if (registry.get(entity, c.Weapon)) |weapon| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Damage: {d}-{d}", .{ weapon.min_damage, weapon.max_damage });
    }
    if (registry.get(entity, c.SourceOfLight)) |light| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Radius of light: {d}", .{light.radius});
    }
    return .{ .title = title, .text_area = text_area };
}

/// true means that the button is recognized
pub fn handleButton(_: *Self, btn: g.Button) !bool {
    return btn.game_button == .a;
}

pub fn draw(self: *const Self, render: g.Render) !void {
    try self.text_area.draw(render);
    // Draw the title
    const reg = self.text_area.region();
    const padding: u8 = @intCast(reg.cols - self.title.len);
    var point = reg.top_left.movedToNTimes(.right, padding / 2);
    for (self.title) |char| {
        try render.runtime.drawSprite(char, point, .normal);
        point.move(.right);
    }
    try render.hideLeftButton();
    try render.drawRightButton(self.right_button_label, false);
}

pub fn close(self: *Self, alloc: std.mem.Allocator, render: g.Render) !void {
    log.debug("Close description window", .{});
    try render.redrawRegionFromSceneBuffer(self.text_area.region());
    self.deinit(alloc);
}
