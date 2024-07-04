const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const Render = @import("Render.zig");
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
systems: [4]System = .{
    ActionSystem.doActions,
    CollisionSystem.handleCollisions,
    DamageSystem.handleDamage,
    updateTarget,
},
/// An entity in player's focus to which a quick action can be applied
target_entity: ?EntityInFocus = null,

pub fn init(session: *game.GameSession, target: game.Entity) PlayMode {
    var mode = PlayMode{ .session = session };
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    if (reachable(session, target, player_position)) |entity| {
        mode.target_entity = .{ .entity = entity };
        mode.calculateQuickActionForTarget(entity, player_position);
    } else {
        mode.findTarget();
    }
    return mode;
}

fn reachable(session: *game.GameSession, target: game.Entity, player_position: p.Point) ?game.Entity {
    if (session.player == target) return null;
    if (session.components.getForEntity(target, game.Sprite)) |s| {
        if (s.position.near(player_position)) return target;
    }
    return null;
}

pub fn handleInput(self: PlayMode, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => {
            var quick_action: game.Action = .wait;
            if (self.target_entity) |target| {
                if (target.quick_action) |qa| quick_action = qa;
            }
            try self.session.components.setToEntity(self.session.player, quick_action);
        },
        game.Buttons.B => {
            try self.session.pause();
        },
        game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
            try self.session.components.setToEntity(self.session.player, game.Action{
                .move = .{
                    .direction = buttons.toDirection().?,
                    .keep_moving = false, // btn.state == .double_pressed,
                },
            });
        },
        else => {},
    }
}

pub fn draw(play_mode: PlayMode) !void {
    // Highlight entity and draw quick action
    if (play_mode.target_entity) |target| {
        try highlightEntityInFocus(play_mode.session, target.entity);
        if (target.quick_action) |qa|
            try drawQuickAction(play_mode.session, qa);
    }
}

fn highlightEntityInFocus(session: *const game.GameSession, entity: game.Entity) !void {
    if (session.components.getForEntity(session.player, game.Sprite)) |player_sprite| {
        if (session.components.getForEntity(entity, game.Sprite)) |target_sprite| {
            if (!player_sprite.position.eql(target_sprite.position))
                try session.runtime.drawSprite(&session.screen, target_sprite, .inverted);
        }
    }
}

fn drawQuickAction(session: *const game.GameSession, quick_action: game.Action) !void {
    switch (quick_action) {
        .open => |door| if (session.components.getForEntity(door, game.Sprite)) |s| {
            try drawLabelAndHighlightQuickActionTarget(session, "Open", s);
        },
        .close => |door| if (session.components.getForEntity(door, game.Sprite)) |s| {
            try drawLabelAndHighlightQuickActionTarget(session, "Close", s);
        },
        .take => |_| {
            // try drawLabelAndHighlightQuickActionTarget(session, "Take");
        },
        .hit => |enemy| {
            // Draw details about the enemy:
            if (session.components.getForEntity(enemy, game.Sprite)) |sprite| {
                if (session.components.getForEntity(enemy, game.Health)) |hp| {
                    if (session.components.getForEntity(enemy, game.Description)) |description| {
                        try drawLabelAndHighlightQuickActionTarget(session, "Attack", sprite);
                        try Render.drawEntityName(session, description.name);
                        try Render.drawEnemyHP(session, hp);
                    }
                }
            }
        },
        else => {},
    }
}

fn drawLabelAndHighlightQuickActionTarget(
    session: *const game.GameSession,
    label: []const u8,
    sprite: *const game.Sprite,
) !void {
    const prompt_position = p.Point{ .row = game.DISPLPAY_ROWS, .col = game.DISPLAY_DUNG_COLS + 2 };
    try session.runtime.drawLabel(label, prompt_position);
    try session.runtime.drawSprite(&session.screen, sprite, .inverted);
}

pub fn openDoor(self: *PlayMode, door: game.Entity) !void {
    if (self.session.components.getForEntity(door, game.Sprite)) |s| {
        try self.session.components.setToEntity(door, game.Door.opened);
        try self.session.components.setToEntity(door, game.Sprite{ .position = s.position, .codepoint = '\'' });
    }
}

pub fn closeDoor(self: *PlayMode, door: game.Entity) !void {
    if (self.session.components.getForEntity(door, game.Sprite)) |s| {
        try self.session.components.setToEntity(door, game.Door.closed);
        try self.session.components.setToEntity(door, game.Sprite{ .position = s.position, .codepoint = '+' });
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    if (!self.keepEntityInFocus())
        self.findTarget();
}

fn findTarget(self: *PlayMode) void {
    const player_position = self.session.components.getForEntity(self.session.player, game.Sprite).?.position;
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
    const sprites = self.session.components.arrayOf(game.Sprite);
    for (sprites.components.items, 0..) |*sprite, idx| {
        if (region.containsPoint(sprite.position)) {
            if (sprites.index_entity.get(@intCast(idx))) |entity| {
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
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    if (self.target_entity) |*target| {
        // Check if we can keep the current quick action and target
        if (target.quick_action) |qa| {
            if (session.components.getForEntity(target.entity, game.Sprite)) |target_sprite| {
                if (player_position.near(target_sprite.position)) {
                    // handle a case when player entered to the door
                    switch (qa) {
                        .open => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .closed and !player_position.eql(target_sprite.position)) return true;
                        },
                        .close => |door| if (session.components.getForEntity(door, game.Door)) |door_state| {
                            if (door_state.* == .opened and !player_position.eql(target_sprite.position)) return true;
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
    if (self.session.components.getForEntity(target_entity, game.Sprite)) |target_sprite| {
        if (player_position.near(target_sprite.position)) {
            if (self.session.components.getForEntity(target_entity, game.Health)) |_| {
                self.target_entity.?.quick_action = .{ .hit = target_entity };
                return;
            }
            if (self.session.components.getForEntity(target_entity, game.Door)) |door| {
                if (!player_position.eql(target_sprite.position))
                    self.target_entity.?.quick_action = switch (door.*) {
                        .opened => .{ .close = target_entity },
                        .closed => .{ .open = target_entity },
                    };
                return;
            }
        }
    }
}
