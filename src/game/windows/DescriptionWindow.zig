const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.windows);

const DescriptionWindow = @This();

const COLS = w.TextArea.COLS;

const Line = w.TextArea.Line;

entity: g.Entity,
title: []const u8,
text_area: w.TextArea,
right_button_label: []const u8 = "Close",

pub fn init(
    alloc: std.mem.Allocator,
    entities: g.EntitiesManager,
    entity: g.Entity,
    dev_mode: bool,
) !DescriptionWindow {
    var title: []const u8 = "";
    var text_area = w.TextArea.init(.modal);
    if (entities.get(entity, c.Description)) |description| {
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
        if (entities.get(entity, c.Position)) |position| {
            line = try text_area.addEmptyLine(alloc, false);
            _ = try std.fmt.bufPrint(line[1..], "Position: {any}", .{position.place});
        }
    }
    if (entities.get(entity, c.EnemyState)) |state| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "State: is {s}", .{@tagName(state.*)});
    }
    if (entities.get(entity, c.Health)) |health| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
    }
    if (entities.get(entity, c.Speed)) |speed| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
    }
    if (entities.get(entity, c.Weapon)) |weapon| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Damage: {d}-{d}", .{ weapon.min_damage, weapon.max_damage });
    }
    if (entities.get(entity, c.SourceOfLight)) |light| {
        const line = try text_area.addEmptyLine(alloc, false);
        _ = try std.fmt.bufPrint(line[1..], "Radius of light: {d}", .{light.radius});
    }
    return .{ .entity = entity, .title = title, .text_area = text_area };
}

pub fn deinit(self: *DescriptionWindow, alloc: std.mem.Allocator) void {
    self.text_area.deinit(alloc);
}

/// true means that the button is recognized
pub fn handleButton(_: *DescriptionWindow, btn: g.Button) !bool {
    return btn.game_button == .a;
}

pub fn draw(self: *const DescriptionWindow, render: g.Render) !void {
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

pub fn close(self: *DescriptionWindow, alloc: std.mem.Allocator, render: g.Render) !void {
    log.debug("Close description window for {any}", .{self.entity});
    try render.redrawRegionFromSceneBuffer(self.text_area.region());
    self.deinit(alloc);
}
