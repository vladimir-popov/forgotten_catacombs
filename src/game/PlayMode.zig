const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

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

pub fn init(session: *game.GameSession) PlayMode {
    var mode = PlayMode{ .session = session };
    mode.findTarget();
    return mode;
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
                    if (session.components.getForEntity(enemy, game.Description)) |desc| {
                        try drawLabelAndHighlightQuickActionTarget(session, "Attack", sprite);
                        try session.runtime.drawLabel(desc.name, .{
                            .row = 5,
                            .col = game.DISPLAY_DUNG_COLS + 2,
                        });
                        var buf: [2]u8 = undefined;
                        const len = std.fmt.formatIntBuf(&buf, hp.hp, 10, .lower, .{});
                        try session.runtime.drawLabel(buf[0..len], .{
                            .row = 6,
                            .col = game.DISPLAY_DUNG_COLS + 2,
                        });
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

fn findTarget(play_mode: *PlayMode) void {
    const player_position = play_mode.session.components.getForEntity(play_mode.session.player, game.Sprite).?.position;
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
    const sprites = play_mode.session.components.arrayOf(game.Sprite);
    for (sprites.components.items, 0..) |*sprite, idx| {
        if (region.containsPoint(sprite.position)) {
            if (sprites.index_entity.get(@intCast(idx))) |entity| {
                if (play_mode.session.player != entity) {
                    play_mode.target_entity = .{ .entity = entity, .quick_action = null };
                    calculateQuickActionForTarget(play_mode.session, player_position, &play_mode.target_entity.?);
                    return;
                }
            }
        }
    }
}

/// Returns true if the focus is kept
fn keepEntityInFocus(play_mode: *PlayMode) bool {
    const session = play_mode.session;
    const player_position = session.components.getForEntity(session.player, game.Sprite).?.position;
    if (play_mode.target_entity) |*target| {
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
            calculateQuickActionForTarget(play_mode.session, player_position, target);
            if (play_mode.target_entity.?.quick_action != null) return true;
        }
    }
    play_mode.target_entity = null;
    return false;
}

fn calculateQuickActionForTarget(
    session: *game.GameSession,
    player_position: p.Point,
    target_entity: *EntityInFocus,
) void {
    if (session.components.getForEntity(target_entity.entity, game.Sprite)) |target_sprite| {
        if (player_position.near(target_sprite.position)) {
            if (session.components.getForEntity(target_entity.entity, game.Health)) |_| {
                target_entity.quick_action = .{ .hit = target_entity.entity };
                return;
            }
            if (session.components.getForEntity(target_entity.entity, game.Door)) |door| {
                if (!player_position.eql(target_sprite.position))
                    target_entity.quick_action = switch (door.*) {
                        .opened => .{ .close = target_entity.entity },
                        .closed => .{ .open = target_entity.entity },
                    };
                return;
            }
        }
    }
}
