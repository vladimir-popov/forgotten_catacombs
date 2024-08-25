//! This is the main mode of the game in which player travel through the dungeons.

const std = @import("std");
const gm = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const AI = @import("AI.zig");
const ActionSystem = @import("ActionSystem.zig");
const CollisionSystem = @import("CollisionSystem.zig");
const DamageSystem = @import("DamageSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const System = *const fn (play_mode: *PlayMode) anyerror!void;

const Enemy = struct {
    session: *gm.GameSession,
    entity: gm.Entity,
    move_points: u8,

    inline fn doMove(self: *Enemy) !bool {
        const spent_mp = try AI.meleeMove(self.session, self.entity, self.move_points);
        self.move_points -= spent_mp;
        return spent_mp > 0;
    }
};

session: *gm.GameSession,
/// List of all enemies on the level
enemies: std.ArrayList(Enemy),
/// Index of the enemy, which should do move on next tick
current_enemy: u8,
/// Is the player should do its move now?
is_player_turn: bool,
/// How many enemies did their move
moved_enemies: u8,
/// Who is attacking the player right now
attacking_entity: ?gm.Entity,
/// Highlighted entity
entity_in_focus: ?gm.Entity,
// An action which could be applied to the entity in focus
quick_action: ?gm.Action,

pub fn init(session: *gm.GameSession) !PlayMode {
    return .{
        .session = session,
        .enemies = std.ArrayList(Enemy).init(session.game.runtime.alloc),
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
pub fn refresh(self: *PlayMode, entity_in_focus: ?gm.Entity) !void {
    self.entity_in_focus = entity_in_focus;
    try self.updateTarget();
    try self.session.game.render.redraw(self.session, self.entity_in_focus);
}

fn handleInput(self: PlayMode, buttons: gm.Buttons) !void {
    switch (buttons.code) {
        gm.Buttons.A => if (self.quick_action) |quick_action| {
            try self.session.components.setToEntity(self.session.player, quick_action);
        },
        gm.Buttons.B => {
            try self.session.pause();
        },
        gm.Buttons.Left, gm.Buttons.Right, gm.Buttons.Up, gm.Buttons.Down => {
            const speed = self.session.components.getForEntityUnsafe(self.session.player, gm.Speed);
            try self.session.components.setToEntity(self.session.player, gm.Action{
                .type = .{
                    .move = .{
                        .direction = buttons.toDirection().?,
                        .keep_moving = false, // btn.state == .double_pressed,
                    },
                },
                .move_points = speed.move_points,
            });
        },
        else => {},
    }
}

pub fn tick(self: *PlayMode) anyerror!void {
    try self.session.game.render.drawAnimationsFrame(self.session, self.entity_in_focus);
    if (self.session.components.getAll(gm.Animation).len > 0)
        return;

    try self.session.game.render.drawScene(self.session, self.entity_in_focus);
    try self.session.game.render.drawQuickActionButton(self.quick_action);
    // we should update target only if player did some action at this tick
    var should_update_target: bool = false;

    if (self.is_player_turn) {
        if (try self.session.game.runtime.readPushedButtons()) |buttons| {
            try self.handleInput(buttons);
            // break this function if the mode was changed
            if (self.session.mode != .play) return;
            // If the player did some action
            if (self.session.components.getForEntity(self.session.player, gm.Action)) |action| {
                self.is_player_turn = false;
                should_update_target = true;
                if (self.entity_in_focus == self.session.player and action.type != .wait)
                    self.entity_in_focus = null;
                try self.updateEnemies(action.move_points);
            }
        }
    } else {
        if (self.current_enemy < self.enemies.items.len) {
            const actor: *Enemy = &self.enemies.items[self.current_enemy];
            if (try actor.doMove()) {
                if (self.session.components.getForEntity(actor.entity, gm.Action)) |action| {
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
    if (self.session.components.getForEntity(self.session.player, gm.Action)) |action| {
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
    var itr = self.session.level.query().get(gm.NPC);
    while (itr.next()) |tuple| {
        try self.enemies.append(.{ .session = self.session, .entity = tuple[0], .move_points = move_points });
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    // If we're not able to do any action with previous entity in focus
    // we should try to change the focus
    if (self.calculateQuickActionForTarget(self.entity_in_focus)) |qa| {
        self.quick_action = qa;
    } else {
        self.entity_in_focus = null;
        self.quick_action = null;
        const player_position = self.session.components.getForEntityUnsafe(self.session.player, gm.Position);
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
        const positions = self.session.components.arrayOf(gm.Position);
        for (positions.components.items, 0..) |position, idx| {
            if (region.containsPoint(position.point)) {
                if (positions.index_entity.get(@intCast(idx))) |entity| {
                    if (entity == self.session.player) continue;
                    if (self.calculateQuickActionForTarget(entity)) |qa| {
                        self.entity_in_focus = entity;
                        self.quick_action = qa;
                        return;
                    }
                }
            }
        }
        // if no other action was found, then use waiting as default
        self.quick_action = waitAction(self.session);
    }
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target_enemy: ?gm.Entity,
) ?gm.Action {
    const target = target_enemy orelse return null;
    if (target == self.session.player) return waitAction(self.session);

    const player_position = self.session.components.getForEntityUnsafe(self.session.player, gm.Position);
    const target_position = self.session.components.getForEntity(target, gm.Position) orelse return null;
    if (player_position.point.near(target_position.point)) {
        if (self.session.components.getForEntity(target, gm.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with gate
            if (!player_position.point.eql(target_position.point)) {
                return null;
            }
            const player_speed = self.session.components.getForEntityUnsafe(self.session.player, gm.Speed).move_points;
            return switch (ladder.*) {
                .up => |upper_ladder| .{ .type = .{ .move_up_on_level = upper_ladder }, .move_points = player_speed },
                .down => |maybe_ladder| if (maybe_ladder) |under_ladder|
                    .{ .type = .{ .move_down_on_level = under_ladder }, .move_points = player_speed }
                else
                    .{ .type = .{ .move_down_on_level = null }, .move_points = player_speed },
            };
        }
        if (self.session.components.getForEntity(target, gm.Health)) |_| {
            const weapon = self.session.components.getForEntityUnsafe(self.session.player, gm.MeleeWeapon);
            return .{
                .type = .{ .hit = target },
                .move_points = weapon.move_points,
            };
        }
        if (self.session.components.getForEntity(target, gm.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            const player_speed = self.session.components.getForEntityUnsafe(self.session.player, gm.Speed).move_points;
            return switch (door.*) {
                .opened => .{ .type = .{ .close = target }, .move_points = player_speed },
                .closed => .{ .type = .{ .open = target }, .move_points = player_speed },
            };
        }
    }
    return null;
}

fn waitAction(session: *gm.GameSession) gm.Action {
    return .{
        .type = .wait,
        .move_points = session.components.getForEntityUnsafe(session.player, gm.Speed).move_points,
    };
}
