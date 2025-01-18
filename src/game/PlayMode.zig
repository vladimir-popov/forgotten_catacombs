//! This is the main mode of the game in which player travel through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const ActionSystem = @import("ActionSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

session: *g.GameSession,
ai: g.AI,
/// The object of player's actions
target_entity: ?g.Entity,
// An action which could be applied to the entity in focus
quick_action: ?g.Action,
is_player_turn: bool = true,

pub fn init(session: *g.GameSession, rand: std.Random) !PlayMode {
    log.debug("Init PlayMode", .{});
    return .{
        .session = session,
        .ai = g.AI{ .session = session, .rand = rand },
        .target_entity = null,
        .quick_action = null,
    };
}

/// Updates the target entity after switching back to the play mode
pub fn update(self: *PlayMode, target_entity: ?g.Entity) !void {
    self.target_entity = target_entity;
    if (target_entity) |ef| if (ef == self.session.level.player) {
        self.target_entity = null;
    };
    log.debug("Update target after refresh", .{});
    try self.updateTarget();
    try self.redraw();
}

fn draw(self: *const PlayMode) !void {
    try self.session.render.drawScene(self.session, self.target_entity, self.quick_action);
    try self.drawInfoBar();
}

fn redraw(self: *const PlayMode) !void {
    try self.session.render.redraw(self.session, self.target_entity, self.quick_action);
    try self.drawInfoBar();
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.session.level.components.getForEntity(self.session.level.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    if (self.quick_action) |qa| {
        switch (qa) {
            .wait => try self.session.render.drawRightButton("Wait"),
            .open => try self.session.render.drawRightButton("Open"),
            .close => try self.session.render.drawRightButton("Close"),
            .hit => try self.session.render.drawRightButton("Attack"),
            .move_to_level => |ladder| switch (ladder.direction) {
                .up => try self.session.render.drawRightButton("Go up"),
                .down => try self.session.render.drawRightButton("Go down"),
            },
            else => try self.session.render.hideRightButton(),
        }
    }
    // Draw the name or health of the target entity
    if (self.target_entity) |entity| {
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

pub fn subscriber(self: *PlayMode) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    switch (event) {
        .player_hit => {
            self.target_entity = event.player_hit.target;
            log.debug("Update target after player hit", .{});
            try self.updateTarget();
        },
        // TODO: Move to level
        .entity_moved => |entity_moved| if (entity_moved.entity == self.session.level.player) {
            try self.session.level.onPlayerMoved(entity_moved);
        },
        else => {},
    }
}

fn handleInput(self: *PlayMode, button: g.Button) !?g.Action {
    if (button.state == .double_pressed) log.debug("Double press of {any}", .{button});
    switch (button.game_button) {
        .a => if (self.quick_action) |action| {
            return action;
        },
        .b => if (button.state == .pressed) {
            try self.session.lookAround();
            // we have to handle changing the state right after this function
            return null;
        },
        .left, .right, .up, .down => {
            return g.Action{
                .move = .{
                    .target = .{ .direction = button.toDirection().? },
                    .keep_moving = false, // btn.state == .double_pressed,
                },
            };
        },
        .cheat => {
            if (self.session.runtime.getCheat()) |cheat| {
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
        },
    }
    return null;
}

pub fn tick(self: *PlayMode) !void {
    try self.draw();
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return;

    if (self.is_player_turn) {
        if (try self.session.runtime.readPushedButtons()) |buttons| {
            const maybe_action = try self.handleInput(buttons);
            // break this function if the mode was changed
            if (self.session.mode != .play) return;
            // If the player did some action
            if (maybe_action) |action| {
                self.is_player_turn = false;
                const speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
                const mp = try ActionSystem.doAction(self.session, self.session.level.player, action, speed.move_points);
                if (mp > 0) {
                    log.debug("Update target after action {any}", .{action});
                    try self.updateTarget();
                    for (self.session.level.components.arrayOf(c.Initiative).components.items) |*initiative| {
                        initiative.move_points += mp;
                    }
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
                const action = self.ai.action(entity, position.point);
                const mp = try ActionSystem.doAction(self.session, entity, action, speed.move_points);
                std.debug.assert(0 < mp and mp <= initiative.move_points);
                initiative.move_points -= mp;
            }
        }
        self.is_player_turn = true;
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    defer {
        const qa_str = if (self.quick_action) |qa| @tagName(qa) else "not defined";
        log.debug("The target entity after update {any}; quick action {s}", .{ self.target_entity, qa_str });
    }
    log.debug("Update target. Current target is {any}", .{self.target_entity});

    // check if quick action still available for target
    if (self.target_entity) |target| if (self.calculateQuickActionForTarget(target)) |qa| {
        self.quick_action = qa;
        return;
    };
    // If we're not able to do any action with previous target
    // we should try to change the target
    try self.tryToFindNewTarget();
}

fn tryToFindNewTarget(self: *PlayMode) !void {
    self.target_entity = null;
    self.quick_action = null;
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
                if (entity == self.session.level.player) continue;
                if (self.calculateQuickActionForTarget(entity)) |qa| {
                    self.target_entity = entity;
                    self.quick_action = qa;
                    return;
                }
            }
        }
    }
    // if no other action was found, then use waiting as default
    self.quick_action = .wait;
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target: g.Entity,
) ?g.Action {
    const player_position = self.session.level.playerPosition();
    const target_position = self.session.level.components.getForEntity(target, c.Position) orelse return null;
    if (player_position.point.near(target_position.point)) {
        if (self.session.level.components.getForEntity(target, c.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with the ladder
            if (!player_position.point.eql(target_position.point)) return null;
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
        if (self.session.level.components.getForEntity(self.session.level.player, c.Weapon)) |weapon| {
            if (self.session.level.components.getForEntity(target, c.Health)) |health| {
                return .{ .hit = .{ .target = target, .target_health = health, .by_weapon = weapon } };
            }
        }
        if (self.session.level.components.getForEntity(target, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            return switch (door.state) {
                .opened => .{ .close = target },
                .closed => .{ .open = target },
            };
        }
    }
    return null;
}
