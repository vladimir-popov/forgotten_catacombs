//! This is the mode in which the player is able to look around,
//! get the info about entities on the screen, and change the target entity.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.looking_around_mode);

const LookingAroundMode = @This();
const ArrayOfEntitiesOnScreen = std.ArrayList(struct { g.Entity, p.Point, g.Codepoint });

alloc: std.mem.Allocator,
session: *g.GameSession,
/// Arrays of entities and their positions on the screen
entities_on_screen: ArrayOfEntitiesOnScreen,
/// Highlighted entity
entity_in_focus: ?g.Entity,
/// The max length of the visible content of the window
/// -2 for borders; -1 for scroll.
window: ?*g.Render.WindowWithDescription = null,

pub fn init(session: *g.GameSession, alloc: std.mem.Allocator) !LookingAroundMode {
    log.debug("Init LookingAroundMode", .{});
    return .{
        .alloc = alloc,
        .session = session,
        .entities_on_screen = ArrayOfEntitiesOnScreen.init(alloc),
        .entity_in_focus = null,
    };
}

pub fn deinit(self: *LookingAroundMode) void {
    self.entities_on_screen.deinit();
}

pub fn refresh(self: *LookingAroundMode) !void {
    self.entity_in_focus = self.session.level.player;
    self.entities_on_screen.clearRetainingCapacity();
    var itr = self.session.level.query().get2(c.Position, c.Sprite);
    while (itr.next()) |tuple| {
        if (self.session.render.viewport.region.containsPoint(tuple[1].point)) {
            const item = try self.entities_on_screen.addOne();
            item.* = .{ tuple[0], tuple[1].point, tuple[2].codepoint };
        }
    }
    try self.session.render.redraw(self.session, self.entity_in_focus, null);
    log.debug("Refresh the LookingAroundMode. {d} entities on screen", .{self.entities_on_screen.items.len});
}

pub fn tick(self: *LookingAroundMode) anyerror!void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a => if (self.window) |window| {
                window.destroy();
                self.window = null;
                try self.session.render.redraw(self.session, self.entity_in_focus, null);
            } else {
                if (self.entity_in_focus) |entity| {
                    self.window = try self.createWindowWithDescription(entity);
                    try self.session.render.drawWindowWithDescription(self.window.?);
                }
            },
            .b => if (btn.state == .pressed) {
                try self.session.play(self.entity_in_focus);
                return;
            },
            .left, .right, .up, .down => {
                self.chooseNextEntity(btn.toDirection().?);
                try self.session.render.drawScene(self.session, self.entity_in_focus, null);
            },
            // ignore cheats in the LookingAroundMode
            .cheat => _ = self.session.runtime.getCheat(),
        }
    }
}

fn chooseNextEntity(self: *LookingAroundMode, direction: p.Direction) void {
    const target_entity = self.entity_in_focus orelse self.session.level.player;
    const target_point = self.session.level.components.getForEntityUnsafe(target_entity, c.Position).point;
    var min_distance: u8 = 255;
    log.debug(
        "Choose an entity from {d} on the screen in {s} direction",
        .{ self.entities_on_screen.items.len, @tagName(direction) },
    );
    for (self.entities_on_screen.items) |tuple| {
        // we should follow the same logic as the render:
        // only entities, which should be drawn, can be in focus
        if (self.session.level.checkVisibility(tuple[1]) == .invisible) {
            log.debug(
                "The entity {d} '{u}' at {any} is invisible. Skip it.",
                .{ tuple[0], tuple[2], tuple[1] },
            );
            continue;
        }

        const d = distance(target_point, tuple[1], direction);
        if (d < min_distance) {
            min_distance = d;
            self.entity_in_focus = tuple[0];
        }
    }
}

/// Calculates the distance between two points in direction with follow logic:
/// 1. calculates the difference with multiplayer between points on the axis related to direction
/// 2. adds the difference between points on the orthogonal axis
inline fn distance(from: p.Point, to: p.Point, direction: p.Direction) u8 {
    switch (direction) {
        .right => {
            if (to.col <= from.col) return 255;
            return ((to.col - from.col) << 2) + sub(to.row, from.row);
        },
        .left => return distance(to, from, .right),
        .down => {
            if (to.row <= from.row) return 255;
            return ((to.row - from.row) << 2) + sub(to.col, from.col);
        },
        .up => return distance(to, from, .down),
    }
}

/// Returns y - x if y > x, or x - y otherwise.
inline fn sub(x: u8, y: u8) u8 {
    return if (y > x) y - x else x - y;
}

fn createWindowWithDescription(
    self: LookingAroundMode,
    entity: g.Entity,
) !*g.Render.WindowWithDescription {
    const window = try g.Render.WindowWithDescription.create(self.alloc);
    var len: usize = 0;
    if (self.session.level.components.getForEntity(entity, c.Description)) |description| {
        len += (try std.fmt.bufPrint(&window.title, "{s}", .{description.name})).len;
    }
    if (true) {
        len += (try std.fmt.bufPrint(window.title[len..], " [id: {d}]", .{entity})).len;
    }
    if (self.session.level.components.getForEntity(entity, c.EnemyState)) |state| {
        const line = try window.addOneLine();
        _ = try std.fmt.bufPrint(line[1..], "State: is {s}", .{@tagName(state.*)});
    }
    if (self.session.level.components.getForEntity(entity, c.Health)) |health| {
        const line = try window.addOneLine();
        _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
    }
    if (self.session.level.components.getForEntity(entity, c.Speed)) |speed| {
        const line = try window.addOneLine();
        _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
    }
    return window;
}

fn statusLine(self: LookingAroundMode, entity: g.Entity, line: []u8) !usize {
    var len: usize = 0;
    if (self.session.level.components.getForEntity(entity, c.Description)) |description| {
        len += (try std.fmt.bufPrint(line[len..], "{s}", .{description.name})).len;

        if (self.session.level.components.getForEntity(entity, c.EnemyState)) |state| {
            len += (try std.fmt.bufPrint(line[len..], " (is {s})", .{@tagName(state.*)})).len;
        }
    }
    if (true) {
        len += (try std.fmt.bufPrint(line[len..], " [id: {d}]", .{entity})).len;
    }
    return len;
}
