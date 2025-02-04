//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const ActionSystem = @import("ActionSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const QuickAction = struct { target: g.Entity, action: g.Action };

session: *g.GameSession,
// The actions which can be applied to the entity in focus
quick_actions: std.ArrayList(QuickAction),
target_idx: usize = 0,
is_player_turn: bool = true,
window: ?g.Window = null,

pub fn init(session: *g.GameSession) PlayMode {
    return .{
        .session = session,
        .quick_actions = std.ArrayList(QuickAction).init(session.alloc),
    };
}

pub fn deinit(self: *PlayMode) void {
    self.quick_actions.deinit();
    if (self.window) |window|
        window.deinit();
}

pub fn update(self: *PlayMode, target_entity: ?g.Entity) !void {
    try self.updateQuickActions(target_entity);
    try self.draw();
}

fn draw(self: *PlayMode) !void {
    if (self.window) |*window| {
        try self.session.render.drawWindow(window);
    } else {
        try self.session.render.drawScene(self.session.level, self.target(), self.quickAction());
    }
    try self.drawInfoBar();
}

inline fn target(self: PlayMode) ?g.Entity {
    return if (self.quick_actions.items[self.target_idx].action == .wait)
        null
    else
        self.quick_actions.items[self.target_idx].target;
}

inline fn quickAction(self: PlayMode) g.Action {
    return self.quick_actions.items[self.target_idx].action;
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
        const name = if (self.session.level.components.getForEntity(entity, c.Description)) |desc|
            desc.name
        else
            "?";
        try self.session.render.drawInfo(name);
    } else {
        try self.session.render.cleanInfo();
    }
}

pub fn handleEvent(self: *PlayMode, event: g.GameSession.Event) !void {
    switch (event) {
        .player_hit => {
            log.debug("Update target after player hit", .{});
            try self.updateQuickActions(event.player_hit.target);
        },
        .entity_moved => |entity_moved| if (entity_moved.entity == self.session.level.player) {
            try self.session.level.onPlayerMoved(entity_moved);
        },
        else => {},
    }
}

fn handleInput(self: *PlayMode) !?g.Action {
    if (try self.session.runtime.readPushedButtons()) |button| {
        switch (button.game_button) {
            .a => {
                if (self.window) |window| {
                    self.target_idx = window.selected_line orelse 0;
                    window.deinit();
                    self.window = null;
                    self.session.render.clearSceneBuffer();
                } else {
                    switch (button.state) {
                        .released => return self.quickAction(),
                        .hold => if (self.quick_actions.items.len > 0)
                            try self.initWindowWithVariants(self.quick_actions.items, self.target_idx),
                    }
                }
                return null;
            },
            .b => if (button.state == .released) {
                return .look_around;
            },
            .left, .right, .up, .down => if (self.window) |*window| {
                if (button.game_button == .up) {
                    window.selectPrev();
                }
                if (button.game_button == .down) {
                    window.selectNext();
                }
                return null;
            } else {
                return g.Action{
                    .move = .{
                        .target = .{ .direction = button.toDirection().? },
                        .keep_moving = false,
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

/// Draw the scene and handle player's input, or makes AI move
/// Returns the next game mode.
pub fn tick(self: *PlayMode) !g.GameSession.Mode.Tag {
    try self.draw();
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return .play_mode;

    if (self.is_player_turn) {
        if (try self.handleInput()) |action| {
            switch (action) {
                .look_around => return .looking_around_mode,
                .move_to_level => |ladder| {
                    try self.session.movePlayerToLevel(ladder);
                    return .play_mode;
                },
                else => {
                    self.is_player_turn = false;
                    const speed =
                        self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
                    const spent_move_points = try ActionSystem.doAction(
                        self.session,
                        self.session.level.player,
                        action,
                        speed.move_points,
                    );
                    if (spent_move_points > 0) {
                        log.debug("Update quick actions after action {any}", .{action});
                        try self.updateQuickActions(self.target());
                        for (self.session.level.components.arrayOf(c.Initiative).components.items) |*initiative| {
                            initiative.move_points += spent_move_points;
                        }
                    }
                },
            }
        }
    } else {
        // NPC turn
        var itr = self.session.level.query().get2(c.Initiative, c.Speed);
        while (itr.next()) |tuple| {
            const entity = tuple[0];
            const initiative = tuple[1];
            const speed = tuple[2];
            if (speed.move_points > initiative.move_points) continue;
            if (self.session.level.components.getForEntity(entity, c.Position)) |position| {
                const action = self.session.ai.action(self.session.level, entity, position.point);
                const spent_move_points = try ActionSystem.doAction(self.session, entity, action, speed.move_points);
                std.debug.assert(0 < spent_move_points and spent_move_points <= initiative.move_points);
                initiative.move_points -= spent_move_points;
            }
        }
        self.is_player_turn = true;
    }
    return .play_mode;
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
    self.window = try g.Window.init(self.quick_actions.allocator);
    for (variants, 0..) |qa, idx| {
        const line = try self.window.?.addOneLine();
        const action_label = qa.action.toString();
        const pad = @divTrunc(g.Window.MAX_WINDOW_WIDTH - action_label.len, 2);
        std.mem.copyForwards(u8, line[pad..], action_label);
        if (idx == selected)
            self.window.?.selected_line = idx;
    }
}
