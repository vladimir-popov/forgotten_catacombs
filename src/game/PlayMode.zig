const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const Render = @import("Render.zig");
const AI = @import("AI.zig");
const ActionSystem = @import("ActionSystem.zig");
const CollisionSystem = @import("CollisionSystem.zig");
const DamageSystem = @import("DamageSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const System = *const fn (play_mode: *PlayMode) anyerror!void;

const EntityInFocus = struct {
    // used to highlight the entity in focus
    entity: game.Entity,
    // An action which could be applied to the entity in focus
    quick_action: game.Action,
};

session: *game.GameSession,
/// List of all enemies on the level
enemies: std.ArrayList(Enemy),
/// Index of the enemy, which should do move on next tick
current_enemy: u8,
/// Is the player should do its move now?
is_player_turn: bool,
/// How many enemies did their move
moved_enemies: u8,
/// Who is attacking the player right now
attacking_entity: ?game.Entity,

pub fn create(session: *game.GameSession) !*PlayMode {
    const self = try session.runtime.alloc.create(PlayMode);
    self.session = session;
    self.enemies = std.ArrayList(Enemy).init(session.runtime.alloc);
    self.current_enemy = 0;
    self.moved_enemies = 0;
    self.is_player_turn = true;
    self.attacking_entity = null;
    return self;
}

pub fn destroy(self: *PlayMode) void {
    self.enemies.deinit();
    self.session.runtime.alloc.destroy(self);
}

/// Updates the target entity after switching back to the play mode
pub fn refresh(self: *PlayMode) !void {
    try updateTarget(self);
    try Render.redraw(self.session);
}

fn handleInput(self: PlayMode, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => if (self.session.quick_action) |quick_action| {
            try self.session.components.setToEntity(self.session.player, quick_action);
        },
        game.Buttons.B => {
            try self.session.pause();
        },
        game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
            const speed = self.session.components.getForEntityUnsafe(self.session.player, game.Speed);
            try self.session.components.setToEntity(self.session.player, game.Action{
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
    try Render.drawAnimationsFrame(self.session);
    if (self.session.components.getAll(game.Animation).len > 0)
        return;

    try Render.drawScene(self.session);
    // we should update target only if player did some action at this tick
    var should_update_target: bool = false;

    if (self.is_player_turn) {
        if (try self.session.runtime.readPushedButtons()) |buttons| {
            try self.handleInput(buttons);
            // break this function if the mode was changed
            if (self.session.mode != .play) return;
            if (self.session.components.getForEntity(self.session.player, game.Action)) |action| {
                self.is_player_turn = false;
                should_update_target = true;
                try self.updateEnemies(action.move_points);
            }
        }
    } else {
        if (self.current_enemy < self.enemies.items.len) {
            const actor: *Enemy = &self.enemies.items[self.current_enemy];
            if (try actor.doMove()) {
                if (self.session.components.getForEntity(actor.entity, game.Action)) |action| {
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
    if (self.session.components.getForEntity(self.session.player, game.Action)) |action| {
        switch (action.type) {
            .hit => |enemy| {
                self.session.entity_in_focus = enemy;
                if (self.calculateQuickActionForTarget(enemy)) |qa| {
                    self.session.quick_action = qa;
                }
            },
            else => {},
        }
    }
    // collision could lead to new actions
    try ActionSystem.doActions(self.session);
    try DamageSystem.handleDamage(self.session);
}

const Enemy = struct {
    session: *game.GameSession,
    entity: game.Entity,
    move_points: u8,

    inline fn doMove(self: *Enemy) !bool {
        const spent_mp = try AI.meleeMove(self.session, self.entity, self.move_points);
        self.move_points -= spent_mp;
        return spent_mp > 0;
    }
};

/// Collect NPC and set them move points
fn updateEnemies(self: *PlayMode, move_points: u8) !void {
    self.current_enemy = 0;
    self.enemies.clearRetainingCapacity();
    var itr = self.session.query.get(game.NPC);
    while (itr.next()) |tuple| {
        try self.enemies.append(.{ .session = self.session, .entity = tuple[0], .move_points = move_points });
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    // If we're not able to do any action with previous entity in focus
    // we should try to change the focus
    if (self.calculateQuickActionForTarget(self.session.entity_in_focus)) |qa| {
        self.session.quick_action = qa;
    } else {
        self.session.entity_in_focus = null;
        self.session.quick_action = null;
        const player_position = self.session.components.getForEntityUnsafe(self.session.player, game.Position).point;
        // Check the nearest entities:
        const region = p.Region{
            .top_left = .{
                .row = @max(player_position.row - 1, 1),
                .col = @max(player_position.col - 1, 1),
            },
            .rows = 3,
            .cols = 3,
        };
        // TODO improve:
        const positions = self.session.components.arrayOf(game.Position);
        for (positions.components.items, 0..) |position, idx| {
            if (region.containsPoint(position.point)) {
                if (positions.index_entity.get(@intCast(idx))) |entity| {
                    if (entity == self.session.player) continue;
                    if (self.calculateQuickActionForTarget(entity)) |qa| {
                        self.session.entity_in_focus = entity;
                        self.session.quick_action = qa;
                        return;
                    }
                }
            }
        }
        // if no other action was found, then use waiting as default
        self.session.quick_action = waitAction(self.session);
    }
}

fn calculateQuickActionForTarget(
    self: *const PlayMode,
    target_enemy: ?game.Entity,
) ?game.Action {
    const target = target_enemy orelse return null;
    if (target == self.session.player) return waitAction(self.session);

    const player_position = self.session.components.getForEntityUnsafe(self.session.player, game.Position).point;
    const target_position = self.session.components.getForEntityUnsafe(target, game.Position).point;
    if (player_position.near(target_position)) {
        if (self.session.components.getForEntity(target, game.Health)) |_| {
            const weapon = self.session.components.getForEntityUnsafe(self.session.player, game.MeleeWeapon);
            return .{
                .type = .{ .hit = target },
                .move_points = weapon.move_points,
            };
        }
        if (self.session.components.getForEntity(target, game.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.eql(target_position)) {
                return null;
            }
            const player_speed = self.session.components.getForEntityUnsafe(self.session.player, game.Speed);
            return switch (door.*) {
                .opened => .{ .type = .{ .close = target }, .move_points = player_speed.move_points },
                .closed => .{ .type = .{ .open = target }, .move_points = player_speed.move_points },
            };
        }
    }
    return null;
}

fn waitAction(session: *game.GameSession) game.Action {
    return .{
        .type = .wait,
        .move_points = session.components.getForEntityUnsafe(session.player, game.Speed).move_points,
    };
}
