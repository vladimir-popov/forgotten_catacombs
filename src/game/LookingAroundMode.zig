//! This is the mode in which the player is able to look around,
//! get the info about entities on the screen, and change the target entity.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.looking_around_mode);

const LookingAroundMode = @This();
const EntitiesOnScreen = std.AutoHashMapUnmanaged(p.Point, std.ArrayListUnmanaged(g.Entity));
const WindowType = enum { description, variants };

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// Map of entities and their positions on the screen
entities_on_screen: EntitiesOnScreen,
/// Highlighted a place in the dungeon
place_in_focus: p.Point = .{},
/// Index of the focused entity in the map with entities on screen
focus_idx: usize = 0,
/// The window to show description or variants
window: ?g.Window = null,

pub fn init(self: *LookingAroundMode, alloc: std.mem.Allocator, session: *g.GameSession) !void {
    log.debug("Init LookingAroundMode", .{});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .session = session,
        .entities_on_screen = EntitiesOnScreen{},
    };
    try self.update();
}

pub fn deinit(self: LookingAroundMode) void {
    self.arena.deinit();
}

fn update(self: *LookingAroundMode) !void {
    const alloc = self.arena.allocator();
    self.entities_on_screen.clearRetainingCapacity();
    var itr = self.session.level.componentsIterator().of(c.Position);
    while (itr.next()) |tuple| {
        const is_inside_viewport = self.session.viewport.region.containsPoint(tuple[1].place);
        // we should follow the same logic as the render:
        // only entities, which should be drawn, can be in focus
        const is_visible = self.session.level.checkVisibility(tuple[1].place) != .invisible;

        if (is_inside_viewport and is_visible) {
            const gop = try self.entities_on_screen.getOrPut(alloc, tuple[1].place);
            if (!gop.found_existing) {
                gop.value_ptr.* = std.ArrayListUnmanaged(g.Entity){};
            }
            try gop.value_ptr.append(alloc, tuple[0]);
            if (tuple[0].eql(self.session.player)) {
                self.place_in_focus = tuple[1].place;
                self.focus_idx = gop.value_ptr.items.len - 1;
            }
        }
    }
    try self.draw();
    log.debug("LookingAroundMode has been refreshed. Entities on screen:\n{any}", .{self.entities_on_screen});
}

inline fn entityInFocus(self: LookingAroundMode) ?g.Entity {
    if (self.entitiesInFocus()) |entities|
        return entities.items[self.focus_idx];

    return null;
}

inline fn entitiesInFocus(self: LookingAroundMode) ?std.ArrayListUnmanaged(g.Entity) {
    if (self.entities_on_screen.get(self.place_in_focus)) |entities|
        return entities;
    return null;
}

inline fn countOfEntitiesInFocus(self: LookingAroundMode) usize {
    if (self.entities_on_screen.get(self.place_in_focus)) |entities|
        return entities.items.len;

    return 0;
}

fn draw(self: *const LookingAroundMode) !void {
    if (self.window) |*window| {
        try self.session.render.drawWindow(window);
    } else {
        try self.session.render.drawScene(self.session, self.entityInFocus(), null);
        try self.drawInfoBar();
    }
}

fn drawInfoBar(self: *const LookingAroundMode) !void {
    if (self.window) |window| {
        switch (window.tagAsEnum(WindowType)) {
            .variants => {
                try self.session.render.hideLeftButton();
                try self.session.render.drawRightButton("Choose", false);
            },
            .description => {
                try self.session.render.hideLeftButton();
                try self.session.render.drawRightButton("Close", false);
            },
        }
    } else {
        try self.session.render.drawLeftButton("Continue");
        try self.session.render.drawRightButton("Describe", self.countOfEntitiesInFocus() > 1);
    }
    // Draw the name or health of the entity in focus
    if (self.entityInFocus()) |entity| {
        var buf: [g.DISPLAY_COLS]u8 = undefined;
        const len = @min(try self.statusLine(entity, &buf), g.Render.MIDDLE_ZONE_LENGTH);
        try self.session.render.drawInfo(buf[0..len]);
    } else {
        try self.session.render.cleanInfo();
    }
}

fn statusLine(self: LookingAroundMode, entity: g.Entity, line: []u8) !usize {
    var len: usize = 0;
    if (self.session.runtime.isDevMode()) {
        len += (try std.fmt.bufPrint(line[len..], "{d}:", .{entity.id})).len;
    }
    if (self.session.entities.get(entity, c.Description)) |description| {
        len += (try std.fmt.bufPrint(line[len..], "{s}", .{description.name()})).len;

        if (self.session.entities.get(entity, c.EnemyState)) |state| {
            len += (try std.fmt.bufPrint(line[len..], "({s})", .{@tagName(state.*)})).len;
        }
    }
    return len;
}

fn closeWindow(self: *LookingAroundMode, window: *g.Window) !void {
    try self.session.render.redrawRegion(window.region());
    window.deinit();
    self.window = null;
}

pub fn tick(self: *LookingAroundMode) anyerror!void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a => if (self.window) |*window| {
                if (window.tag == @intFromEnum(WindowType.variants)) {
                    self.focus_idx = window.selected_line orelse 0;
                }
                try self.closeWindow(window);
                try self.drawInfoBar();
            } else {
                if (btn.state == .hold and self.countOfEntitiesInFocus() > 1) {
                    if (self.entitiesInFocus()) |entities| {
                        try self.initWindowWithVariants(entities.items, self.focus_idx);
                        try self.session.render.drawWindow(&self.window.?);
                        try self.drawInfoBar();
                    }
                } else if (self.entityInFocus()) |entity| {
                    try self.initWindowWithDescription(entity);
                    try self.session.render.drawWindow(&self.window.?);
                    try self.drawInfoBar();
                }
            },
            .b => if (btn.state == .released and self.window == null) {
                try self.session.play(self.entityInFocus());
                return;
            },
            .left, .right, .up, .down => if (self.window) |*window| {
                if (window.tag == @intFromEnum(WindowType.variants)) {
                    if (btn.game_button == .up) {
                        window.selectPreviousLine();
                        try self.session.render.drawWindow(window);
                        try self.drawInfoBar();
                    }
                    if (btn.game_button == .down) {
                        window.selectNextLine();
                        try self.session.render.drawWindow(window);
                        try self.drawInfoBar();
                    }
                }
            } else {
                self.place_in_focus = chooseNextEntity(
                    self.place_in_focus,
                    btn.toDirection().?,
                    self.entities_on_screen,
                );
                self.focus_idx = 0;
                try self.draw();
            },
        }
    }
}

fn chooseNextEntity(
    current_place: p.Point,
    direction: p.Direction,
    entities_on_screen: EntitiesOnScreen,
) p.Point {
    var nearest_place = current_place;
    var min_distance: f16 = std.math.floatMax(f16);
    var itr = entities_on_screen.iterator();
    while (itr.next()) |entry| {
        const place = entry.key_ptr.*;

        const d: f16 = distance(current_place, place, direction);
        log.debug("Distance to {any} is {d} (entity {any})", .{ place, d, entry.value_ptr.items });

        if (d > 0 and d < min_distance) {
            log.debug("New closest place {any}. min {d}", .{ place, d });
            min_distance = d;
            nearest_place = place;
        }
    }
    return nearest_place;
}

/// Returns the distance between two points. If the target point is outside of the region
/// for the specified direction, this function returns max(f16).
///
///    Example:
///  ------
/// |  *   |
/// |  |  *|
/// |  f-->|
/// |  |*  |
/// |  |   |
///  ------
///  Only two points should have a distance in right direction. The point is on the border should
///  not be count.
inline fn distance(from: p.Point, to: p.Point, direction: p.Direction) f16 {
    const in_the_direction = switch (direction) {
        .up => to.row < from.row,
        .down => to.row > from.row,
        .left => to.col < from.col,
        .right => to.col > from.col,
    };
    if (in_the_direction)
        return from.distanceTo(to)
    else
        return std.math.floatMax(f16);
}

/// Returns y - x if y > x, or x - y otherwise.
inline fn sub(x: u8, y: u8) u8 {
    return if (y > x) y - x else x - y;
}

fn initWindowWithVariants(
    self: *LookingAroundMode,
    variants: []const g.Entity,
    selected: usize,
) !void {
    self.window = g.Window.modal(self.arena.allocator());
    self.window.?.setEnumTag(WindowType.variants);
    for (variants, 0..) |entity, idx| {
        // Every entity has to have description, or handling indexes become complicated
        const description = self.session.entities.getUnsafe(entity, c.Description);
        const line = try self.window.?.addEmptyLine();
        const pad = @divTrunc(g.Window.MAX_WINDOW_WIDTH - description.name().len, 2);
        std.mem.copyForwards(u8, line[pad..], description.name());
        if (idx == selected)
            self.window.?.selected_line = idx;
    }
}

fn initWindowWithDescription(
    self: *LookingAroundMode,
    entity: g.Entity,
) !void {
    self.window = g.Window.modal(self.arena.allocator());
    self.window.?.setEnumTag(WindowType.description);
    try self.window.?.info(self.session.entities, entity, self.session.runtime.isDevMode());
}
