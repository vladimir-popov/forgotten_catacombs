//! This is the mode in which the player is able to look around,
//! get the info about entities on the screen, and change the target entity.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.looking_around_mode);

const LookingAroundMode = @This();
const EntitiesOnScreen = std.AutoHashMap(p.Point, std.ArrayListUnmanaged(g.Entity));
const WindowType = enum { desription, variants };

arena: *std.heap.ArenaAllocator,
session: *g.GameSession,
/// Map of entities and their positions on the screen
entities_on_screen: EntitiesOnScreen,
/// Highlighted place in the dungeon
place_in_focus: ?p.Point,
/// Index of the entity in focus
focus_idx: usize = 0,
/// The window to show description or variants
window: ?*g.Window,

pub fn init(alloc: std.mem.Allocator, session: *g.GameSession) !LookingAroundMode {
    log.debug("Init LookingAroundMode", .{});
    const arena = try alloc.create(std.heap.ArenaAllocator);
    arena.* = std.heap.ArenaAllocator.init(alloc);
    return .{
        .arena = arena,
        .session = session,
        .entities_on_screen = EntitiesOnScreen.init(arena.allocator()),
        .place_in_focus = null,
        .window = null,
    };
}

pub fn deinit(self: *LookingAroundMode) void {
    const alloc = self.arena.child_allocator;
    self.arena.deinit();
    alloc.destroy(self.arena);
}

pub fn refresh(self: *LookingAroundMode) !void {
    _ = self.arena.reset(.retain_capacity);
    self.window = null;

    const alloc = self.arena.allocator();
    self.entities_on_screen = EntitiesOnScreen.init(self.arena.allocator());
    var itr = self.session.level.query().get(c.Position);
    while (itr.next()) |tuple| {
        if (self.session.render.viewport.region.containsPoint(tuple[1].point)) {
            const gop = try self.entities_on_screen.getOrPut(tuple[1].point);
            if (!gop.found_existing) {
                gop.value_ptr.* = try std.ArrayListUnmanaged(g.Entity).initCapacity(alloc, 1);
            }
            try gop.value_ptr.append(alloc, tuple[0]);
            if (tuple[0] == self.session.level.player) {
                self.place_in_focus = tuple[1].point;
                self.focus_idx = gop.value_ptr.items.len - 1;
            }
        }
    }
    try self.redraw();
    log.debug("LookingAroundMode has been refreshed. Entities on screen:\n{any}", .{self.entities_on_screen});
}

inline fn entityInFocus(self: LookingAroundMode) ?g.Entity {
    if (self.entitiesInFocus()) |entities|
        return entities.items[self.focus_idx];

    return null;
}

inline fn entitiesInFocus(self: LookingAroundMode) ?std.ArrayListUnmanaged(g.Entity) {
    if (self.place_in_focus) |place|
        if (self.entities_on_screen.get(place)) |entities|
            return entities;

    return null;
}

inline fn countOfEntitiesInFocus(self: LookingAroundMode) usize {
    if (self.place_in_focus) |place|
        if (self.entities_on_screen.get(place)) |entities|
            return entities.items.len;

    return 0;
}

fn draw(self: *const LookingAroundMode) !void {
    try self.session.render.drawScene(self.session, self.entityInFocus(), null);
    try self.drawInfoBar();
}

fn redraw(self: *const LookingAroundMode) !void {
    try self.session.render.redraw(self.session, self.entityInFocus(), null);
    try self.drawInfoBar();
}

fn drawInfoBar(self: *const LookingAroundMode) !void {
    if (self.window) |window| {
        if (window.tag == @intFromEnum(WindowType.variants)) {
            try self.session.render.hideLeftButton();
            try self.session.render.drawRightButton("Choose", false);
        } else {
            try self.session.render.hideLeftButton();
            try self.session.render.drawRightButton("Close", false);
        }
    } else {
        try self.session.render.drawLeftButton("Continue");
        try self.session.render.drawRightButton("Describe", self.countOfEntitiesInFocus() > 1);
    }
    // Draw the name or health of the entity in focus
    if (self.entityInFocus()) |entity| {
        if (entity != self.session.level.player) {
            if (self.session.level.components.getForEntity3(entity, c.Sprite, c.Health, c.Position)) |tuple| {
                if (tuple[3].point.eql(self.session.level.playerPosition().point)) {
                    try self.session.render.drawEnemyHealth(tuple[1].codepoint, tuple[2]);
                } else {
                    var buf: [g.DISPLAY_COLS]u8 = undefined;
                    const len = @min(try self.statusLine(entity, &buf), g.Render.MIDDLE_ZONE_LENGTH);
                    try self.session.render.drawInfo(buf[0..len]);
                }
                return;
            }
        }
        const name = if (self.session.level.components.getForEntity(entity, c.Description)) |desc|
            desc.name
        else
            "?";
        try self.session.render.drawInfo(name);
    } else {
        try self.session.render.cleanInfo();
    }
}

fn statusLine(self: LookingAroundMode, entity: g.Entity, line: []u8) !usize {
    var len: usize = 0;
    if (true) {
        len += (try std.fmt.bufPrint(line[len..], "{d}:", .{entity})).len;
    }
    if (self.session.level.components.getForEntity(entity, c.Description)) |description| {
        len += (try std.fmt.bufPrint(line[len..], "{s}", .{description.name})).len;

        if (self.session.level.components.getForEntity(entity, c.EnemyState)) |state| {
            len += (try std.fmt.bufPrint(line[len..], "({s})", .{@tagName(state.*)})).len;
        }
    }
    return len;
}

pub fn tick(self: *LookingAroundMode) anyerror!void {
    // Nothing should happened until the player push a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.game_button) {
            .a => if (self.window) |window| {
                if (window.tag == @intFromEnum(WindowType.variants)) {
                    self.focus_idx = window.selected_line orelse 0;
                }
                window.destroy();
                self.window = null;
                try self.redraw();
            } else {
                if (btn.state == .hold and self.countOfEntitiesInFocus() > 1) {
                    if (self.entitiesInFocus()) |entities| {
                        self.window = try self.createWindowWithVariants(entities.items, self.focus_idx);
                        try self.session.render.drawWindow(self.window.?);
                        try self.drawInfoBar();
                    }
                } else if (self.entityInFocus()) |entity| {
                    self.window = try self.createWindowWithDescription(entity);
                    try self.session.render.drawWindow(self.window.?);
                    try self.drawInfoBar();
                }
            },
            .b => if (btn.state == .released and self.window == null) {
                try self.session.play(self.entityInFocus());
                return;
            },
            .left, .right, .up, .down => if (self.window) |window| {
                if (window.tag == @intFromEnum(WindowType.variants)) {
                    if (btn.game_button == .up) {
                        window.selectPrev();
                        try self.session.render.drawWindow(window);
                        try self.drawInfoBar();
                    }
                    if (btn.game_button == .down) {
                        window.selectNext();
                        try self.session.render.drawWindow(window);
                        try self.drawInfoBar();
                    }
                }
            } else {
                self.chooseNextEntity(btn.toDirection().?);
                try self.draw();
            },
        }
    }
}

fn chooseNextEntity(self: *LookingAroundMode, direction: p.Direction) void {
    var min_distance: u8 = 255;
    var itr = self.entities_on_screen.iterator();
    while (itr.next()) |entry| {
        const place = entry.key_ptr.*;
        // we should follow the same logic as the render:
        // only entities, which should be drawn, can be in focus
        if (self.session.level.checkVisibility(place) == .invisible)
            continue;

        const d = if (self.place_in_focus) |current_place|
            distance(current_place, place, direction)
        else
            0;

        if (d < min_distance) {
            min_distance = d;
            self.place_in_focus = place;
            self.focus_idx = 0;
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

fn createWindowWithVariants(
    self: LookingAroundMode,
    variants: []const g.Entity,
    selected: usize,
) !*g.Window {
    const window = try g.Window.create(self.arena.allocator());
    window.tag = @intFromEnum(WindowType.variants);
    for (variants, 0..) |entity, idx| {
        // Every entity has to have description, or handling indexes become complicated
        const description = self.session.level.components.getForEntityUnsafe(entity, c.Description);
        const line = try window.addOneLine();
        const pad = @divTrunc(g.Window.MAX_WINDOW_WIDTH - description.name.len, 2);
        std.mem.copyForwards(u8, line[pad..], description.name);
        if (idx == selected)
            window.selected_line = idx;
    }
    return window;
}

fn createWindowWithDescription(
    self: LookingAroundMode,
    entity: g.Entity,
) !*g.Window {
    const window = try g.Window.create(self.arena.allocator());
    window.tag = @intFromEnum(WindowType.desription);
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
