//! In this mode the player is able to look around,
//! get an info about entities on the screen, and change the target entity.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.explore_mode);

const Self = @This();
const EntitiesOnScreen = std.AutoHashMapUnmanaged(p.Point, [c.Position.ZOrder.count]?g.Entity);

session: *g.GameSession,
/// Map of entities and their positions on the screen
entities_on_screen: EntitiesOnScreen,
entity_in_focus: g.Entity,
/// Highlighted a focused place in the dungeon
place_in_focus: p.Point,
compositor: w.WindowCompositor(Self),

pub fn init(self: *Self, session: *g.GameSession) !void {
    self.* = .{
        .session = session,
        .entity_in_focus = session.player,
        .place_in_focus = session.level.playerPosition().place,
        .entities_on_screen = .empty,
        .compositor = .init(
            session.mode_arena.allocator(),
            self,
            w.FULL_SCREEN_REGION,
        ),
    };
    try self.updateEntitiesOnScreen();
    try self.draw(self.session.render);
}

pub fn tick(self: *Self) anyerror!void {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (try self.compositor.handleButton(btn) == .close_window) {
            try self.session.continuePlay(self.entity_in_focus, null);
            return;
        }
        try self.compositor.draw(self.session.render);
    }
}

pub fn handleButton(self: *Self, btn: g.Button) !w.HandleButtonResult {
    switch (btn.game_button) {
        .b => {
            if (btn.state == .hold and self.countOfEntitiesInFocus() > 1) {
                if (self.entitiesInFocus()) |entities| {
                    try self.showWindowWithEntities(entities);
                }
            } else {
                try self.showWindowWithEntityDescription();
            }
        },
        .a => {
            return .close_window;
        },
        .left, .right, .up, .down => {
            self.moveFocus(btn.toDirection().?);
        },
    }
    return .keep_open;
}

pub fn draw(self: *Self, render: g.Render) !void {
    try render.drawScene(self.session, self.entity_in_focus);
    try render.drawLeftButton("Describe", self.countOfEntitiesInFocus() > 1);
    if (self.canBeATarget()) {
        try render.drawRightButton("Target", false);
    } else {
        try render.drawRightButton("Cancel", false);
    }
    // Draw the name or health of the entity in focus
    var buf: [g.DISPLAY_COLS]u8 = undefined;
    const len = @min(try self.statusLine(self.entity_in_focus, &buf), g.Render.INFO_ZONE_LENGTH);
    try render.drawInfo(buf[0..len]);
}

inline fn isLevelUp(self: Self) bool {
    return self.entity_in_focus.eql(self.session.player) and
        g.meta.isLevelUp(&self.session.registry, self.session.player);
}

fn canBeATarget(self: *const Self) bool {
    const weapon = g.meta.getWeapon(&self.session.registry, self.session.player);
    const player_position = self.session.level.playerPosition();
    return self.session.actions.calculateQuickActionForTarget(
        player_position.place,
        weapon[1],
        self.entity_in_focus,
    ) != null;
}

fn statusLine(self: Self, entity: g.Entity, line: []u8) !usize {
    var len: usize = 0;
    if (self.session.runtime.isDevMode()) {
        len += (try std.fmt.bufPrint(line[len..], "{d}:", .{entity.id})).len;
    }
    len += (try g.Description.printActualName(line[len..], self.session.journal, entity)).len;
    if (self.session.registry.get(entity, c.EnemyState)) |state| {
        len += (try std.fmt.bufPrint(line[len..], "({s})", .{@tagName(state.*)})).len;
    }
    return len;
}

fn updateEntitiesOnScreen(self: *Self) !void {
    const alloc = self.session.mode_arena.allocator();
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
        if (level.checkPlaceVisibility(place) != .invisible) {
            const gop = try self.entities_on_screen.getOrPut(alloc, place);
            if (!gop.found_existing) {
                gop.value_ptr.* = @splat(null);
            }
            gop.value_ptr[@intFromEnum(zorder)] = entity;
        }
    }
    log.debug("ExploreMode has been refreshed. Entities on screen:\n{any}", .{self.entities_on_screen});
}

fn entitiesInFocus(self: Self) ?[c.Position.ZOrder.count]?g.Entity {
    if (self.entities_on_screen.get(self.place_in_focus)) |entities|
        return entities;
    return null;
}

fn countOfEntitiesInFocus(self: Self) usize {
    var count: usize = 0;
    if (self.entities_on_screen.get(self.place_in_focus)) |entities| {
        for (entities) |entity| {
            if (entity != null)
                count += 1;
        }
    }

    return count;
}

fn moveFocus(self: *Self, direction: p.Direction) void {
    var nearest_place = self.place_in_focus;
    var min_distance: f32 = std.math.floatMax(f32);
    var itr = self.entities_on_screen.iterator();
    while (itr.next()) |entry| {
        const place = entry.key_ptr.*;
        const d: f32 = distance(self.place_in_focus, place, direction);
        if (d > 0 and d < min_distance) {
            min_distance = d;
            nearest_place = place;
        }
    }
    self.place_in_focus = nearest_place;
    const entities = self.entities_on_screen.get(nearest_place).?;
    for (g.utils.reverse(c.Position.ZOrder.indexes)) |idx| {
        if (entities[idx]) |entity| {
            self.entity_in_focus = entity;
            return;
        }
    }
}

/// Returns the distance between two points. If the target point is outside of the region
/// for the specified direction, this function returns max(f32).
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
fn distance(from: p.Point, to: p.Point, direction: p.Direction) f32 {
    const in_the_direction = switch (direction) {
        .up => to.row < from.row,
        .down => to.row > from.row,
        .left => to.col < from.col,
        .right => to.col > from.col,
    };
    if (in_the_direction)
        return from.distanceTo(to)
    else
        return std.math.floatMax(f32);
}

/// Returns y - x if y > x, or x - y otherwise.
inline fn sub(x: u8, y: u8) u8 {
    return if (y > x) y - x else x - y;
}

fn showWindowWithEntities(
    self: *Self,
    variants: [c.Position.ZOrder.count]?g.Entity,
) !void {
    const window = try self.compositor.showModalWindowWithOptions(
        self.session.mode_arena.allocator(),
        &.{},
        g.Entity,
        self,
        .center,
    );
    for (variants) |maybe_entity| {
        if (maybe_entity) |entity| {
            var buf: [32]u8 = undefined;
            _ = try window.panel.area.addOption(
                try g.Description.printActualName(&buf, self.session.journal, entity),
                entity,
                .{ .handle_release_button = showEntityDescription },
            );
            if (entity.eql(self.entity_in_focus))
                // the variants array has to have at least one (focused) entity
                try window.panel.area.selectLine(window.panel.area.options.items.len - 1);
        }
    }
}

fn showEntityDescription(ptr: *anyopaque, _: usize, entity: g.Entity) anyerror!w.HandleButtonResult {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.entity_in_focus = entity;
    try self.showWindowWithEntityDescription();
    return .keep_open;
}

fn showWindowWithEntityDescription(self: *Self) !void {
    try self.compositor.showEntityDescription(
        self.session.mode_arena.allocator(),
        self.session,
        self.entity_in_focus,
    );
}
