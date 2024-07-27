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

const EntityInFocus = struct {
    entity: game.Entity,
    quick_action: ?game.Action = null,
};

const PlayMode = @This();

const System = *const fn (play_mode: *PlayMode) anyerror!void;

session: *game.GameSession,
actors: std.ArrayList(Actor),
/// Index of the actor, which should do move on next tick
current_actor: u8,
/// Is the player should do its move now?
players_move: bool,
/// How many actors except player did their move
moved_actors: u8,
/// An entity in player's focus to which a quick action can be applied
target_entity: ?EntityInFocus,
/// How is attacking the player right now
attacking_entity: ?game.Entity,

pub fn create(session: *game.GameSession) !*PlayMode {
    const self = try session.runtime.alloc.create(PlayMode);
    self.session = session;
    self.actors = std.ArrayList(Actor).init(session.runtime.alloc);
    self.current_actor = 0;
    self.moved_actors = 0;
    self.players_move = true;
    self.target_entity = null;
    self.attacking_entity = null;
    return self;
}

pub fn destroy(self: *PlayMode) void {
    self.actors.deinit();
    self.session.runtime.alloc.destroy(self);
}

pub fn refresh(self: *PlayMode, target: game.Entity) void {
    const player_position = self.session.components.getForEntityUnsafe(self.session.player, game.Position).point;
    if (reachable(self.session, target, player_position)) |entity| {
        self.target_entity = .{ .entity = entity };
        self.calculateQuickActionForTarget(entity, player_position);
    } else {
        self.findTarget();
    }
}

inline fn reachable(session: *game.GameSession, target: game.Entity, player_position: p.Point) ?game.Entity {
    if (session.player == target) return null;
    if (session.components.getForEntity(target, game.Position)) |position| {
        if (position.point.near(player_position)) return target;
    }
    return null;
}

pub fn tick(self: *PlayMode) anyerror!void {
    try Render.render(self.session);
    if (self.session.components.getAll(game.Animation).len > 0)
        return;

    if (self.players_move) {
        if (try self.session.runtime.readPushedButtons()) |buttons| {
            try self.handleInput(buttons);
            if (self.session.components.getForEntity(self.session.player, game.Action)) |action| {
                self.players_move = false;
                try self.updateActors(action.move_points);
            }
        }
    } else {
        if (self.current_actor < self.actors.items.len) {
            const actor: *Actor = &self.actors.items[self.current_actor];
            if (try actor.doMove()) {
                if (self.session.components.getForEntity(actor.entity, game.Action)) |action| {
                    if (action.type == .hit) {
                        self.attacking_entity = actor.entity;
                    }
                }
                self.moved_actors += 1;
            }
            self.current_actor += 1;
        } else {
            self.players_move = self.moved_actors == 0;
            self.current_actor = 0;
            self.moved_actors = 0;
            self.attacking_entity = null;
        }
    }
    _ = try self.runSystems();
}

const Actor = struct {
    session: *game.GameSession,
    entity: game.Entity,
    move_points: u8,

    inline fn doMove(self: *Actor) !bool {
        const spent_mp = try AI.meleeMove(self.session, self.entity, self.move_points);
        self.move_points -= spent_mp;
        return spent_mp > 0;
    }
};

fn updateActors(self: *PlayMode, move_points: u8) !void {
    self.current_actor = 0;
    self.actors.clearRetainingCapacity();
    var itr = self.session.query.get(game.NPC);
    while (itr.next()) |tuple| {
        try self.actors.append(.{ .session = self.session, .entity = tuple[0], .move_points = move_points });
    }
}

fn runSystems(self: *PlayMode) !void {
    try ActionSystem.doActions(self.session);
    try CollisionSystem.handleCollisions(self.session);
    try DamageSystem.handleDamage(self.session);
    try updateTarget(self);
    try Render.render(self.session);
}

pub fn handleInput(self: PlayMode, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => {
            const speed = self.session.components.getForEntityUnsafe(self.session.player, game.Speed);
            var quick_action: game.Action = .{ .type = .wait, .move_points = speed.move_points };
            if (self.target_entity) |target| {
                if (target.quick_action) |qa| quick_action = qa;
            }
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

/// Highlight entity and draw quick action
pub fn draw(self: *const PlayMode) !void {
    if (self.attacking_entity) |entity| {
        try highlightEntity(self.session, entity);
    } else if (self.target_entity) |target| {
        try highlightEntity(self.session, target.entity);
    }
    if (self.target_entity) |target| if (target.quick_action) |qa|
        try drawQuickAction(self.session, qa);
}

fn highlightEntity(session: *const game.GameSession, entity: game.Entity) !void {
    const target_position = session.components.getForEntityUnsafe(entity, game.Position);
    const sprite = session.components.getForEntityUnsafe(entity, game.Sprite);
    try session.runtime.drawSprite(&session.screen, sprite, target_position, .inverted);
}

fn drawQuickAction(session: *const game.GameSession, quick_action: game.Action) !void {
    switch (quick_action.type) {
        .open => try drawLabel(session, "Open"),
        .close => try drawLabel(session, "Close"),
        .take => |_| {
            // try drawLabelAndHighlightQuickActionTarget(session, "Take");
        },
        .hit => |enemy| {
            // Draw details about the enemy:
            if (session.components.getForEntity(enemy, game.Health)) |hp| {
                if (session.components.getForEntity(enemy, game.Description)) |description| {
                    try drawLabel(session, "Attack");
                    try Render.drawEntityName(session, description.name);
                    try Render.drawEnemyHP(session, hp);
                }
            }
        },
        else => {},
    }
}

fn drawLabel(
    session: *const game.GameSession,
    label: []const u8,
) !void {
    const prompt_position = p.Point{ .row = game.DISPLPAY_ROWS, .col = game.DISPLAY_DUNG_COLS + 2 };
    try session.runtime.drawText(label, prompt_position);
}

fn updateTarget(self: *PlayMode) anyerror!void {
    if (!self.keepEntityInFocus())
        self.findTarget();
}

fn findTarget(self: *PlayMode) void {
    const player_position = self.session.components.getForEntityUnsafe(self.session.player, game.Position).point;
    // TODO improve:
    // Check the nearest entities:
    const region = p.Region{
        .top_left = .{
            .row = @max(player_position.row - 1, 1),
            .col = @max(player_position.col - 1, 1),
        },
        .rows = 3,
        .cols = 3,
    };
    const positions = self.session.components.arrayOf(game.Position);
    for (positions.components.items, 0..) |position, idx| {
        if (region.containsPoint(position.point)) {
            if (positions.index_entity.get(@intCast(idx))) |entity| {
                if (self.session.player != entity) {
                    self.target_entity = .{ .entity = entity, .quick_action = null };
                    self.calculateQuickActionForTarget(entity, player_position);
                    return;
                }
            }
        }
    }
}

/// Returns true if the focus is kept
fn keepEntityInFocus(self: *PlayMode) bool {
    const session = self.session;
    const player_position = session.components.getForEntityUnsafe(session.player, game.Position).point;
    if (self.target_entity) |*target| {
        // Check if we can keep the current quick action and target
        if (target.quick_action) |qa| {
            if (session.components.getForEntity(target.entity, game.Position)) |target_position| {
                if (player_position.near(target_position.point)) {
                    // handle a case when player entered to the door
                    switch (qa.type) {
                        .open => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .closed and !player_position.eql(target_position.point)) return true;
                        },
                        .close => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .opened and !player_position.eql(target_position.point)) return true;
                        },
                        else => return true,
                    }
                }
            }
        } else {
            self.calculateQuickActionForTarget(target.entity, player_position);
            if (self.target_entity.?.quick_action != null) return true;
        }
    }
    self.target_entity = null;
    return false;
}

fn calculateQuickActionForTarget(
    self: *PlayMode,
    target_entity: game.Entity,
    player_position: p.Point,
) void {
    if (self.session.components.getForEntity(target_entity, game.Position)) |target_position| {
        if (player_position.near(target_position.point)) {
            if (self.session.components.getForEntity(target_entity, game.Health)) |_| {
                const weapon = self.session.components.getForEntityUnsafe(self.session.player, game.MeleeWeapon);
                self.target_entity.?.quick_action = .{
                    .type = .{ .hit = target_entity },
                    .move_points = weapon.move_points,
                };
                return;
            }
            if (self.session.components.getForEntity(target_entity, game.Door)) |door| {
                if (!player_position.eql(target_position.point)) {
                    const speed = self.session.components.getForEntityUnsafe(self.session.player, game.Speed);
                    self.target_entity.?.quick_action = switch (door.*) {
                        .opened => .{ .type = .{ .close = target_entity }, .move_points = speed.move_points },
                        .closed => .{ .type = .{ .open = target_entity }, .move_points = speed.move_points },
                    };
                }
            }
        }
    }
}
