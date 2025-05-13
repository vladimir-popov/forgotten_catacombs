//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

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
quick_actions_window: ?w.OptionsWindow(void) = null,

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

pub fn tick(self: *PlayMode) !void {
    try self.draw();
    if (self.session.entities.getAll(c.Animation).len > 0)
        return;

    if (self.is_player_turn) {
        const maybe_action = try self.handleInput();
        // break this function if the mode was changed
        if (self.session.mode != .play) return;
        // If the player did some action
        if (maybe_action) |action| {
            self.is_player_turn = false;
            const speed = self.session.entities.getUnsafe(self.session.player, c.Speed);
            const mp = try self.session.doAction(self.session.player, action, speed.move_points);
            if (mp > 0) {
                log.debug("Update quick actions after action {any}", .{action});
                try self.updateQuickActions(self.target());
                var itr = self.session.level.componentsIterator().of(c.Initiative);
                while (itr.next()) |initiative| {
                    initiative[1].move_points += mp;
                }
            }
        }
    } else {
        var itr = self.session.level.componentsIterator().of4(c.Position, c.Initiative, c.Speed, c.EnemyState);
        while (itr.next()) |tuple| {
            const entity, const position, const initiative, const speed, const state = tuple;
            if (speed.move_points > initiative.move_points) continue;

            const action = self.session.ai.action(entity, position.place, state.*);
            const mp = try self.session.doAction(entity, action, speed.move_points);
            std.debug.assert(0 < mp and mp <= initiative.move_points);
            initiative.move_points -= mp;
        }
        self.is_player_turn = true;
    }
}

fn handleInput(self: *PlayMode) !?g.Action {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.quick_actions_window) |*window| {
            if (btn.game_button == .b) {
                try window.close(self.arena.allocator(), self.session.render);
                self.quick_actions_window = null;
            } else {
                _ = try window.handleButton(btn);
                try window.draw(self.session.render);
            }
        } else {
            switch (btn.game_button) {
                .a => switch (btn.state) {
                    .released => return self.quickAction(),
                    .hold => if (self.quick_actions.items.len > 0) {
                        self.quick_actions_window =
                            try self.windowWithQuickActions(self.quick_actions.items, self.target_idx);
                        try self.quick_actions_window.?.draw(self.session.render);
                        return null;
                    },
                },
                .b => if (btn.state == .released) {
                    try self.session.lookAround();
                    // we have to handle changing the state right after this function
                    return null;
                },
                .left, .right, .up, .down => {
                    return g.Action{
                        .move = .{
                            .target = .{ .direction = btn.toDirection().? },
                            .keep_moving = false, // btn.state == .double_pressed,
                        },
                    };
                },
            }
        }
    }
    if (self.session.runtime.popCheat()) |cheat| {
        log.debug("Cheat {any}", .{cheat});
        switch (cheat) {
            .dump_vector_field => self.session.level.dijkstra_map.dumpToLog(),
            .turn_light_on => g.visibility.turn_light_on = true,
            .turn_light_off => g.visibility.turn_light_on = false,
            .set_health => |hp| {
                if (self.session.entities.get(self.session.player, c.Health)) |health| {
                    health.current = hp;
                }
            },
            else => if (cheat.toAction(self.session)) |action| {
                return action;
            },
        }
    }
    return null;
}

fn draw(self: *const PlayMode) !void {
    if (self.quick_actions_window == null) {
        try self.session.render.drawScene(self.session, self.target(), self.quickAction());
        try self.drawInfoBar();
    }
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.session.entities.get(self.session.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    try self.session.render.drawLeftButton("Explore");
    const qa = self.quickAction();
    const action_label = qa.toString();
    try self.session.render.drawRightButton(action_label, self.quick_actions.items.len > 1);

    // Draw the name or health of the target entity
    if (self.target()) |entity| {
        if (!entity.eql(self.session.player)) {
            if (self.session.entities.get2(entity, c.Sprite, c.Health)) |tuple| {
                try self.session.render.drawEnemyHealth(tuple[0].codepoint, tuple[1]);
                return;
            }
        }
        const name = if (self.session.entities.get(entity, c.Description)) |desc| desc.name() else "?";
        try self.session.render.drawInfo(name);
    } else {
        try self.session.render.cleanInfo();
    }
}

fn target(self: PlayMode) ?g.Entity {
    return if (self.target_idx > self.quick_actions.items.len - 1)
        null
    else if (self.quick_actions.items[self.target_idx].action == .wait)
        null
    else
        self.quick_actions.items[self.target_idx].target;
}

fn quickAction(self: PlayMode) g.Action {
    return self.quick_actions.items[self.target_idx].action;
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
        if (tg.id != self.session.player.id) {
            // check if quick action is available for target
            if (self.calculateQuickActionForTarget(tg)) |qa| {
                try self.quick_actions.append(self.arena.allocator(), .{ .target = tg, .action = qa });
            }
        }
    }
    const player_position = self.session.level.playerPosition();
    // Check the nearest entities:
    // TODO improve:
    var itr = self.session.level.componentsIterator().of(c.Position);
    while (itr.next()) |tuple| {
        const entity: g.Entity, const position: *c.Position = tuple;
        if (position.place.near(player_position.place)) {
            if (entity.eql(self.session.player) or entity.eql(target_entity)) continue;
            log.debug(
                "The place {any} near the player {any} with {any}",
                .{ position.place, player_position.place, entity },
            );
            if (self.calculateQuickActionForTarget(entity)) |qa| {
                log.debug("Calculated action is {any}", .{qa});
                try self.quick_actions.append(self.arena.allocator(), .{ .target = entity, .action = qa });
            } else {
                log.warn("No quick action for entity {any}", .{entity});
            }
        }
    }
    // player should always be able to wait
    try self.quick_actions.append(self.arena.allocator(), .{ .target = self.session.player, .action = .wait });
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target_entity: g.Entity,
) ?g.Action {
    const player_position = self.session.level.playerPosition();
    const target_position =
        self.session.entities.get(target_entity, c.Position) orelse return null;

    if (player_position.place.eql(target_position.place)) {
        if (self.session.entities.get(target_entity, c.ZOrder)) |zorder| {
            if (zorder.order == .item) {
                return .{ .pickup = target_entity };
            }
        }
        if (self.session.entities.get(target_entity, c.Ladder)) |ladder| {
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
    }

    if (player_position.place.near(target_position.place)) {
        if (self.session.isEnemy(target_entity)) {
            if (self.session.getWeapon(self.session.player)) |weapon| {
                return .{ .hit = .{ .target = target_entity, .by_weapon = weapon.* } };
            }
        }
        if (self.session.entities.get(target_entity, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.place.eql(target_position.place)) {
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

fn windowWithQuickActions(
    self: *PlayMode,
    variants: []const QuickAction,
    selected: usize,
) !w.OptionsWindow(void) {
    var window = w.OptionsWindow(void).init(self, .modal, "Close", "Choose");
    for (variants, 0..) |qa, idx| {
        try window.addOption(self.arena.allocator(), qa.action.toString(), {}, chooseEntity, null);
        if (idx == selected)
            window.selected_line = idx;
    }
    return window;
}

fn chooseEntity(ptr: *anyopaque, line_idx: usize, _: void) anyerror!void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    self.target_idx = line_idx;
}
