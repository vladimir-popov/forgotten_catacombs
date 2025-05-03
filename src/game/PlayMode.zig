//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const QuickAction = struct { target: g.Entity, action: g.Action };

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
// The actions which can be applied to the entity in focus
quick_actions: std.ArrayListUnmanaged(QuickAction),
// The index of the quick action for the target entity
target_idx: usize = 0,
is_player_turn: bool = true,
window: ?g.Window = null,

pub fn init(
    self: *PlayMode,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    target_entity: ?g.Entity,
) !void {
    log.debug("Init PlayMode", .{});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .session = session,
        .quick_actions = std.ArrayListUnmanaged(QuickAction){},
    };
    try self.updateQuickActions(target_entity);
    try self.draw();
}

pub fn deinit(self: PlayMode) void {
    self.arena.deinit();
}

inline fn target(self: PlayMode) ?g.Entity {
    return if (self.target_idx > self.quick_actions.items.len - 1)
        null
    else if (self.quick_actions.items[self.target_idx].action == .wait)
        null
    else
        self.quick_actions.items[self.target_idx].target;
}

inline fn quickAction(self: PlayMode) g.Action {
    return self.quick_actions.items[self.target_idx].action;
}

fn draw(self: *const PlayMode) !void {
    if (self.window) |*window| {
        try self.session.render.drawWindow(window);
    } else {
        try self.session.render.drawScene(self.session, self.target(), self.quickAction());
        try self.drawInfoBar();
    }
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.window) |_| {
        try self.session.render.hideLeftButton();
        try self.session.render.drawRightButton("Choose", false);
        return;
    }

    if (self.session.level.components.getForEntity(self.session.level.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    const qa = self.quickAction();
    const action_label = qa.toString();
    try self.session.render.drawRightButton(action_label, self.quick_actions.items.len > 1);

    // Draw the name or health of the target entity
    if (self.target()) |entity| {
        if (entity != self.session.level.player) {
            if (self.session.level.components.getForEntity2(entity, c.Sprite, c.Health)) |tuple| {
                try self.session.render.drawEnemyHealth(tuple[1].codepoint, tuple[2]);
                return;
            }
        }
        const name = if (self.session.level.components.getForEntity(entity, c.Description)) |desc| desc.name else "?";
        try self.session.render.drawInfo(name);
    } else {
        try self.session.render.cleanInfo();
    }
}

fn closeWindow(self: *PlayMode, window: *g.Window) !void {
    try self.session.render.redrawRegion(window.region());
    window.deinit();
    self.window = null;
}

fn handleInput(self: *PlayMode) !?g.Action {
    if (try self.session.runtime.readPushedButtons()) |button| {
        switch (button.game_button) {
            .a => {
                if (self.window) |*window| {
                    self.target_idx = window.selected_line orelse 0;
                    try self.closeWindow(window);
                    try self.drawInfoBar();
                } else {
                    switch (button.state) {
                        .released => return self.quickAction(),
                        .hold => if (self.quick_actions.items.len > 0) {
                            try self.initWindowWithVariants(self.quick_actions.items, self.target_idx);
                            try self.draw();
                        },
                    }
                }
                return null;
            },
            .b => if (button.state == .released) {
                try self.session.lookAround();
                // we have to handle changing the state right after this function
                return null;
            },
            .left, .right, .up, .down => if (self.window) |*window| {
                if (button.game_button == .up) {
                    window.selectPreviousLine();
                    try self.session.render.drawWindow(window);
                    try self.drawInfoBar();
                }
                if (button.game_button == .down) {
                    window.selectNextLine();
                    try self.session.render.drawWindow(window);
                    try self.drawInfoBar();
                }
                return null;
            } else {
                return g.Action{
                    .move = .{
                        .target = .{ .direction = button.toDirection().? },
                        .keep_moving = false, // btn.state == .double_pressed,
                    },
                };
            },
        }
    }
    if (self.session.runtime.popCheat()) |cheat| {
        log.debug("Cheat {any}", .{cheat});
        switch (cheat) {
            .dump_vector_field => self.session.level.dijkstra_map.dumpToLog(),
            .turn_light_on => g.visibility.turn_light_on = true,
            .turn_light_off => g.visibility.turn_light_on = false,
            else => if (cheat.toAction(self.session)) |action| {
                return action;
            },
        }
    }
    return null;
}

pub fn tick(self: *PlayMode) !void {
    try self.draw();
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return;

    if (self.is_player_turn) {
        const maybe_action = try self.handleInput();
        // break this function if the mode was changed
        if (self.session.mode != .play) return;
        // If the player did some action
        if (maybe_action) |action| {
            self.is_player_turn = false;
            const speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            const mp = try self.session.doAction(self.session.level.player, action, speed.move_points);
            if (mp > 0) {
                log.debug("Update quick actions after action {any}", .{action});
                try self.updateQuickActions(self.target());
                for (self.session.level.components.arrayOf(c.Initiative).components.items) |*initiative| {
                    initiative.move_points += mp;
                }
            }
        }
    } else {
        var itr = self.session.level.query().get2(c.Initiative, c.Speed);
        while (itr.next()) |tuple| {
            const entity = tuple[0];
            const initiative = tuple[1];
            const speed = tuple[2];
            if (speed.move_points > initiative.move_points) continue;
            if (self.session.level.components.getForEntity(entity, c.Position)) |position| {
                const action = self.session.ai.action(entity, position.point);
                const mp = try self.session.doAction(entity, action, speed.move_points);
                std.debug.assert(0 < mp and mp <= initiative.move_points);
                initiative.move_points -= mp;
            }
        }
        self.is_player_turn = true;
    }
}

pub fn updateQuickActions(self: *PlayMode, target_entity: ?g.Entity) anyerror!void {
    defer {
        log.debug(
            "After update {d} quick actions: {any}",
            .{ self.quick_actions.items.len, self.quick_actions.items },
        );
    }

    self.quick_actions.clearRetainingCapacity();
    self.target_idx = 0;

    if (target_entity) |tg| {
        if (tg != self.session.level.player) {
            // check if quick action is available for target
            if (self.calculateQuickActionForTarget(tg)) |qa| {
                try self.quick_actions.append(self.arena.allocator(), .{ .target = tg, .action = qa });
            }
        }
    }
    const player_position = self.session.level.playerPosition();
    // Check the nearest entities:
    const region = p.Region{
        .top_left = .{
            .row = @max(player_position.point.row - 1, 1),
            .col = @max(player_position.point.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    };
    // TODO improve:
    const positions = self.session.level.components.arrayOf(c.Position);
    for (positions.components.items, 0..) |position, idx| {
        if (region.containsPoint(position.point)) {
            if (positions.index_entity.get(@intCast(idx))) |entity| {
                if (entity == self.session.level.player or entity == target_entity) continue;
                if (self.calculateQuickActionForTarget(entity)) |qa| {
                    try self.quick_actions.append(self.arena.allocator(), .{ .target = entity, .action = qa });
                }
            }
        }
    }
    // player should always be able to wait
    try self.quick_actions.append(self.arena.allocator(), .{ .target = self.session.level.player, .action = .wait });
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target_entity: g.Entity,
) ?g.Action {
    const player_position = self.session.level.playerPosition();
    const target_position =
        self.session.level.components.getForEntity(target_entity, c.Position) orelse return null;

    if (player_position.point.near(target_position.point)) {
        if (self.session.level.components.getForEntity(target_entity, c.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with the ladder
            if (!player_position.point.eql(target_position.point)) return null;
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
        if (self.session.level.components.getForEntity(self.session.level.player, c.Weapon)) |weapon| {
            if (self.session.level.components.getForEntity(target_entity, c.Health)) |health| {
                return .{ .hit = .{ .target = target_entity, .target_health = health, .by_weapon = weapon } };
            }
        }
        if (self.session.level.components.getForEntity(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            return switch (door.state) {
                .opened => .{ .close = target_entity },
                .closed => .{ .open = target_entity },
            };
        }
    }
    return null;
}

fn initWindowWithVariants(
    self: *PlayMode,
    variants: []const QuickAction,
    selected: usize,
) !void {
    self.window = g.Window.init(self.arena.allocator());
    for (variants, 0..) |qa, idx| {
        const line = try self.window.?.addOneLine();
        const action_label = qa.action.toString();
        const pad = @divTrunc(g.Window.MAX_WINDOW_WIDTH - action_label.len, 2);
        std.mem.copyForwards(u8, line[pad..], action_label);
        if (idx == selected)
            self.window.?.selected_line = idx;
    }
}
