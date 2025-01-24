//! This is the main mode of the game in which player travel through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const ActionSystem = @import("ActionSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const QuickAction = struct { target: g.Entity, action: g.Action };

session: *g.GameSession,
ai: g.AI,
// The actions which can be applied to the entity in focus
quick_actions: std.ArrayList(QuickAction),
is_player_turn: bool = true,

pub fn init(arena: *std.heap.ArenaAllocator, session: *g.GameSession, rand: std.Random) !PlayMode {
    log.debug("Init PlayMode", .{});
    return .{
        .session = session,
        .ai = g.AI{ .session = session, .rand = rand },
        .quick_actions = std.ArrayList(QuickAction).init(arena.allocator()),
    };
}

/// Updates the target entity after switching back to the play mode
pub fn update(self: *PlayMode, target_entity: ?g.Entity) !void {
    log.debug("Update target after refresh", .{});
    try self.updateQuickActions(target_entity);
    try self.redraw();
}

inline fn target(self: PlayMode) ?g.Entity {
    return if (self.quick_actions.items[0].action == .wait)
        null
    else
        self.quick_actions.items[0].target;
}

inline fn quickAction(self: PlayMode) g.Action {
    return self.quick_actions.items[0].action;
}

fn draw(self: *const PlayMode) !void {
    try self.session.render.drawScene(self.session, self.target(), self.quickAction());
    try self.drawInfoBar();
}

fn redraw(self: *const PlayMode) !void {
    try self.session.render.redraw(self.session, self.target(), self.quickAction());
    try self.drawInfoBar();
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.session.level.components.getForEntity(self.session.level.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    switch (self.quickAction()) {
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

pub fn subscriber(self: *PlayMode) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    switch (event) {
        .player_hit => {
            log.debug("Update target after player hit", .{});
            try self.updateQuickActions(event.player_hit.target);
        },
        // TODO: Move to level
        .entity_moved => |entity_moved| if (entity_moved.entity == self.session.level.player) {
            try self.session.level.onPlayerMoved(entity_moved);
        },
        else => {},
    }
}

fn handleInput(self: *PlayMode) !?g.Action {
    if (try self.session.runtime.readPushedButtons()) |button| {
        switch (button.game_button) {
            .a => if (button.state == .released) return self.quickAction(),
            .b => if (button.state == .released) {
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
            const mp = try ActionSystem.doAction(self.session, self.session.level.player, action, speed.move_points);
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
                const action = self.ai.action(entity, position.point);
                const mp = try ActionSystem.doAction(self.session, entity, action, speed.move_points);
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

    if (target_entity) |tg| {
        if (tg != self.session.level.player) {
            // check if quick action is available for target
            if (self.calculateQuickActionForTarget(tg)) |qa| {
                try self.quick_actions.append(.{ .target = tg, .action = qa });
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
                    try self.quick_actions.append(.{ .target = entity, .action = qa });
                }
            }
        }
    }
    // player should always be able to wait
    try self.quick_actions.append(.{ .target = self.session.level.player, .action = .wait });
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target_entity: g.Entity,
) ?g.Action {
    const player_position = self.session.level.playerPosition();
    const target_position = self.session.level.components.getForEntity(target_entity, c.Position) orelse return null;
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
