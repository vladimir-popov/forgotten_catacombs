//! This is the mode in which the player is able to look around,
//! get the info about entities on the screen, and change the target entity.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.explore_mode);

const ExploreMode = @This();
const EntitiesOnScreen = std.AutoHashMapUnmanaged(p.Point, [3]?g.Entity);

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
/// Map of entities and their positions on the screen
entities_on_screen: EntitiesOnScreen,
entity_in_focus: g.Entity,
/// Highlighted a focused place in the dungeon
place_in_focus: p.Point,
/// The window to show list of entities on the place in focus
entities_window: ?w.ModalWindow(w.OptionsArea(g.Entity)) = null,
description_window: ?w.ModalWindow(w.TextArea) = null,

pub fn init(self: *ExploreMode, alloc: std.mem.Allocator, session: *g.GameSession) !void {
    log.debug("Init LookingAroundMode", .{});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .session = session,
        .entity_in_focus = session.player,
        .place_in_focus = session.level.playerPosition().place,
        .entities_on_screen = .empty,
    };
    try self.updateEntitiesOnScreen();
    try self.draw();
}

pub fn deinit(self: ExploreMode) void {
    self.arena.deinit();
}

pub fn tick(self: *ExploreMode) anyerror!void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.description_window) |*description_window| {
            if (try description_window.handleButton(btn)) {
                try description_window.hide(self.session.render, .from_buffer);
                description_window.deinit(self.arena.allocator());
                self.description_window = null;
            }
        } else if (self.entities_window) |*entities_window| {
            if (try entities_window.handleButton(btn)) {
                try entities_window.hide(self.session.render, .from_buffer);
                entities_window.deinit(self.arena.allocator());
                self.entities_window = null;
            }
        } else {
            switch (btn.game_button) {
                .a => {
                    if (btn.state == .hold and self.countOfEntitiesInFocus() > 1) {
                        if (self.entitiesInFocus()) |entities| {
                            self.entities_window = try self.windowWithEntities(entities);
                        }
                    } else {
                        self.description_window = try self.windowWithDescription();
                    }
                },
                .b => {
                    try self.session.continuePlay(self.entity_in_focus, null);
                    return;
                },
                .left, .right, .up, .down => {
                    self.moveFocus(btn.toDirection().?);
                },
            }
        }
        try self.draw();
    }
}

fn draw(self: *const ExploreMode) !void {
    if (self.description_window) |*window| {
        try window.draw(self.session.render);
    } else if (self.entities_window) |*window| {
        try window.draw(self.session.render);
    } else {
        try self.session.render.drawScene(self.session, self.entity_in_focus);
        try self.session.render.drawLeftButton("Continue", false);
        try self.session.render.drawRightButton("Describe", self.countOfEntitiesInFocus() > 1);
        // Draw the name or health of the entity in focus
        var buf: [g.DISPLAY_COLS]u8 = undefined;
        const len = @min(try self.statusLine(self.entity_in_focus, &buf), g.Render.INFO_ZONE_LENGTH);
        try self.session.render.drawInfo(buf[0..len]);
    }
}

fn statusLine(self: ExploreMode, entity: g.Entity, line: []u8) !usize {
    var len: usize = 0;
    if (self.session.runtime.isDevMode()) {
        len += (try std.fmt.bufPrint(line[len..], "{d}:", .{entity.id})).len;
    }
    len += (try std.fmt.bufPrint(line[len..], "{s}", .{g.meta.name(&self.session.registry, entity)})).len;
    if (self.session.registry.get(entity, c.EnemyState)) |state| {
        len += (try std.fmt.bufPrint(line[len..], "({s})", .{@tagName(state.*)})).len;
    }
    return len;
}

fn updateEntitiesOnScreen(self: *ExploreMode) !void {
    const alloc = self.arena.allocator();
    self.entities_on_screen.clearRetainingCapacity();
    const level = &self.session.level;
    var itr = level.registry.query(c.Position);
    while (itr.next()) |tuple| {
        const entity = tuple[0];
        const place = tuple[1].place;
        const zorder = tuple[1].zorder;
        if (!self.session.viewport.region.containsPoint(place))
            continue;

        // we should follow the same logic as the render:
        // only entities, which should be drawn, can be in focus
        if (level.checkVisibility(place) != .invisible) {
            const gop = try self.entities_on_screen.getOrPut(alloc, place);
            if (!gop.found_existing) {
                gop.value_ptr.* = @splat(null);
            }
            gop.value_ptr[@intFromEnum(zorder)] = entity;
        }
    }
    log.debug("ExploreMode has been refreshed. Entities on screen:\n{any}", .{self.entities_on_screen});
}

fn entitiesInFocus(self: ExploreMode) ?[3]?g.Entity {
    if (self.entities_on_screen.get(self.place_in_focus)) |entities|
        return entities;
    return null;
}

fn countOfEntitiesInFocus(self: ExploreMode) usize {
    var count: usize = 0;
    if (self.entities_on_screen.get(self.place_in_focus)) |entities| {
        for (entities) |entity| {
            if (entity != null)
                count += 1;
        }
    }

    return count;
}

fn moveFocus(self: *ExploreMode, direction: p.Direction) void {
    var nearest_place = self.place_in_focus;
    var min_distance: f16 = std.math.floatMax(f16);
    var itr = self.entities_on_screen.iterator();
    while (itr.next()) |entry| {
        const place = entry.key_ptr.*;
        const d: f16 = distance(self.place_in_focus, place, direction);
        if (d > 0 and d < min_distance) {
            min_distance = d;
            nearest_place = place;
        }
    }
    self.place_in_focus = nearest_place;
    const entities = self.entities_on_screen.get(nearest_place).?;
    for (&[3]u8{ 2, 1, 0 }) |idx| {
        if (entities[idx]) |entity| {
            self.entity_in_focus = entity;
            return;
        }
    }
}

/// Returns the distance between two points. If the target point is outside of the region
/// for the specified direction, this function returns max(f16).
///
///    Example:
///  ------
/// |  o   |
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

fn windowWithEntities(
    self: *ExploreMode,
    variants: [3]?g.Entity,
) !w.ModalWindow(w.OptionsArea(g.Entity)) {
    var window = w.options(g.Entity, self);
    for (variants) |maybe_entity| {
        if (maybe_entity) |entity| {
            try window.area.addOption(
                self.arena.allocator(),
                g.meta.name(&self.session.registry, entity),
                entity,
                showEntityDescription,
                null,
            );
            if (entity.eql(self.entity_in_focus))
                // the variants array has to have at least one (focused) entity
                try window.area.selectLine(window.area.options.items.len - 1);
        }
    }
    return window;
}

fn showEntityDescription(ptr: *anyopaque, _: usize, entity: g.Entity) anyerror!void {
    const self: *ExploreMode = @ptrCast(@alignCast(ptr));
    self.entity_in_focus = entity;
    self.description_window = try self.windowWithDescription();
}

fn windowWithDescription(self: *ExploreMode) !w.ModalWindow(w.TextArea) {
    return try w.entityDescription(
        self.arena.allocator(),
        self.session,
        self.entity_in_focus,
    );
}
