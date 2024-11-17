//! This is the main mode of the game in which player travel through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const AI = @import("AI.zig");
const ActionSystem = @import("ActionSystem.zig");
const CollisionSystem = @import("CollisionSystem.zig");
const DamageSystem = @import("DamageSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const System = *const fn (play_mode: *PlayMode) anyerror!void;

const Enemy = struct {
    session: *g.GameSession,
    entity: g.Entity,
    move_points: u8,

    inline fn doMove(self: *Enemy) !bool {
        const spent_mp = try AI.meleeMove(self.session, self.entity, self.move_points);
        self.move_points -= spent_mp;
        return spent_mp > 0;
    }
};

session: *g.GameSession,
/// List of all enemies on the level
enemies: std.ArrayList(Enemy),
/// Index of the enemy, which should do move on next tick
current_enemy: u8,
/// Is the player should do its move now?
is_player_turn: bool,
/// How many enemies did their move
moved_enemies: u8,
/// Who is attacking the player right now
attacking_entity: ?g.Entity,
/// Highlighted entity
entity_in_focus: ?g.Entity,
// An action which could be applied to the entity in focus
quick_action: ?c.Action,

pub fn init(session: *g.GameSession, alloc: std.mem.Allocator) !PlayMode {
    return .{
        .session = session,
        .enemies = std.ArrayList(Enemy).init(alloc),
        .current_enemy = 0,
        .moved_enemies = 0,
        .is_player_turn = true,
        .attacking_entity = null,
        .entity_in_focus = null,
        .quick_action = null,
    };
}

pub fn deinit(self: PlayMode) void {
    self.enemies.deinit();
}

/// Updates the target entity after switching back to the play mode
pub fn refresh(self: *PlayMode, entity_in_focus: ?g.Entity) !void {
    self.entity_in_focus = entity_in_focus;
    if (entity_in_focus) |ef| if (ef == self.session.level.player) {
        self.entity_in_focus = null;
    };
    try self.updateTarget();
    try self.session.render.redraw(self.session, self.entity_in_focus);
}

fn handleInput(self: *PlayMode, button: g.Button) !void {
    if (button.state == .double_pressed) log.info("Double press of {any}", .{button});
    switch (button.game_button) {
        .a => if (self.quick_action) |quick_action| {
            try self.session.level.components.setToEntity(self.session.level.player, quick_action);
        },
        .b => if (button.state == .pressed) {
            try self.session.explore();
        },
        .left, .right, .up, .down => {
            const speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            try self.session.level.components.setToEntity(self.session.level.player, c.Action{
                .type = .{
                    .move = .{
                        .direction = button.toDirection().?,
                        .keep_moving = false, // btn.state == .double_pressed,
                    },
                },
                .move_points = speed.move_points,
            });
        },
        .cheat => {
            if (self.session.runtime.getCheat()) |cheat| {
                log.debug("Cheat {any}", .{cheat});
                switch (cheat) {
                    .refresh_screen => {
                        self.session.viewport.centeredAround(self.session.level.playerPosition().point);
                        try self.session.render.redraw(self.session, self.entity_in_focus);
                    },
                    .move_player_to_entrance => {
                        var itr = self.session.level.query().get2(c.Ladder, c.Position);
                        while (itr.next()) |tuple| {
                            if (tuple[1].direction == .up) {
                                try self.movePlayerToPoint(tuple[2].point);
                            }
                        }
                    },
                    .move_player_to_exit => {
                        var itr = self.session.level.query().get2(c.Ladder, c.Position);
                        while (itr.next()) |tuple| {
                            if (tuple[1].direction == .down) {
                                try self.movePlayerToPoint(tuple[2].point);
                            }
                        }
                    },
                    .move_player => |point_on_screen| {
                        const screen_corner = self.session.viewport.region.top_left;
                        try self.movePlayerToPoint(.{
                            .row = point_on_screen.row + screen_corner.row,
                            .col = point_on_screen.col + screen_corner.col,
                        });
                    },
                }
            }
        },
    }
}

// used in cheats only
fn movePlayerToPoint(self: *PlayMode, point: p.Point) !void {
    std.log.debug("Move player to {any}", .{point});
    try self.session.level.components.setToEntity(
        self.session.level.player,
        c.Position{ .point = point },
    );
    try self.updateTarget();
    self.session.viewport.centeredAround(point);
    try self.session.render.redraw(self.session, self.entity_in_focus);
}

pub fn tick(self: *PlayMode) anyerror!void {
    try self.session.render.drawScene(self.session, self.entity_in_focus);
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return;

    try self.session.render.drawQuickActionButton(self.quick_action);
    // we should update target only if player did some action at this tick
    var should_update_target: bool = false;

    if (self.is_player_turn) {
        if (try self.session.runtime.readPushedButtons()) |buttons| {
            try self.handleInput(buttons);
            // break this function if the mode was changed
            if (self.session.mode != .play) return;
            // If the player did some action
            if (self.session.level.components.getForEntity(self.session.level.player, c.Action)) |action| {
                self.is_player_turn = false;
                should_update_target = true;
                try self.updateEnemies(action.move_points);
            }
        }
    } else {
        if (self.current_enemy < self.enemies.items.len) {
            const actor: *Enemy = &self.enemies.items[self.current_enemy];
            if (try actor.doMove()) {
                if (self.session.level.components.getForEntity(actor.entity, c.Action)) |action| {
                    if (action.type == .hit) {
                        self.attacking_entity = actor.entity;
                    }
                }
                self.moved_enemies += 1;
            }
            self.current_enemy += 1;
        } else {
            self.is_player_turn = self.moved_enemies == 0;
            self.current_enemy = 0;
            self.moved_enemies = 0;
            self.attacking_entity = null;
        }
    }
    try self.runSystems();
    if (should_update_target) try self.updateTarget();
}

fn runSystems(self: *PlayMode) !void {
    try ActionSystem.doActions(self.session);
    try CollisionSystem.handleCollisions(self.session);
    // if the player had collision with enemy, that enemy should appear in focus
    if (self.session.level.components.getForEntity(self.session.level.player, c.Action)) |action| {
        switch (action.type) {
            .hit => |enemy| {
                self.entity_in_focus = enemy;
                if (self.calculateQuickActionForTarget(enemy)) |qa| {
                    self.quick_action = qa;
                }
            },
            else => {},
        }
    }
    // collision could lead to new actions
    try ActionSystem.doActions(self.session);
    try DamageSystem.handleDamage(self.session);
}

/// Collect NPC and set them move points
fn updateEnemies(self: *PlayMode, move_points: u8) !void {
    self.current_enemy = 0;
    self.enemies.clearRetainingCapacity();
    var itr = self.session.level.query().get(c.NPC);
    while (itr.next()) |tuple| {
        try self.enemies.append(.{ .session = self.session, .entity = tuple[0], .move_points = move_points });
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    defer {
        const qa_str = if (self.quick_action) |qa| @tagName(qa.type) else "not defined";
        log.debug("Entity in focus {any}; quick action {s}", .{ self.entity_in_focus, qa_str });
    }

    // check if quick action still available for target
    if (self.entity_in_focus) |target| if (self.calculateQuickActionForTarget(target)) |qa| {
        self.quick_action = qa;
        return;
    };
    // If we're not able to do any action with previous entity in focus
    // we should try to change the focus
    try self.tryToFindNewTarget();
}

fn tryToFindNewTarget(self: *PlayMode) !void {
    self.entity_in_focus = null;
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
                    self.entity_in_focus = entity;
                    self.quick_action = qa;
                    return;
                }
            }
        }
    }
    // if no other action was found, then use waiting as default
    self.quick_action = .{
        .type = .wait,
        .move_points = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed).move_points,
    };
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target: g.Entity,
) ?c.Action {
    const player_position = self.session.level.playerPosition();
    const target_position = self.session.level.components.getForEntity(target, c.Position) orelse return null;
    if (player_position.point.near(target_position.point)) {
        if (self.session.level.components.getForEntity(target, c.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with the ladder
            if (!player_position.point.eql(target_position.point)) return null;
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            const player_speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            return .{ .type = .{ .move_to_level = ladder.* }, .move_points = player_speed.move_points };
        }
        if (self.session.level.components.getForEntity(target, c.Health)) |_| {
            const weapon = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.MeleeWeapon);
            return .{
                .type = .{ .hit = target },
                .move_points = weapon.move_points,
            };
        }
        if (self.session.level.components.getForEntity(target, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            const player_speed =
                self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            return switch (door.state) {
                .opened => .{ .type = .{ .close = target }, .move_points = player_speed.move_points },
                .closed => .{ .type = .{ .open = target }, .move_points = player_speed.move_points },
            };
        }
    }
    return null;
}
