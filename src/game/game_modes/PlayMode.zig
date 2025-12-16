//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

pub const QuickActions = struct {
    // The actions which can be applied to the entity in focus
    actions: std.ArrayListUnmanaged(g.actions.Action) = .empty,
    // The index of the quick action for the target entity
    selected_idx: usize = 0,

    fn reset(self: *QuickActions) void {
        self.actions.clearRetainingCapacity();
        self.selected_idx = 0;
    }
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
// The entity to which a quick actions can be applied
target: ?g.Entity = null,
quick_actions: QuickActions,
is_player_turn: bool = true,
quick_actions_window: ?w.ModalWindow(w.OptionsArea(void)) = null,

pub fn init(
    self: *PlayMode,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
    target: ?g.Entity,
) !void {
    log.debug("Init PlayMode. Target is {any}", .{target});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .session = session,
        .target = target,
        .quick_actions = .{},
    };
    try self.updateQuickActions();
    try self.session.render.drawHorizontalLine(
        '═',
        .{ .row = self.session.viewport.region.rows + 1, .col = 1 },
        self.session.viewport.region.cols,
    );
}

pub fn deinit(self: PlayMode) void {
    self.arena.deinit();
}

pub fn tick(self: *PlayMode) !void {
    if (try self.draw()) return;

    if (self.is_player_turn) {
        // break this function if no input
        const action = (try self.handleInput()) orelse return;
        if (try self.doTurn(self.session.player, action)) |actual_action| {
            switch (actual_action) {
                .hit => |enemy| {
                    self.setTarget(enemy);
                },
                .open => |door| {
                    self.setTarget(door.id);
                },
                else => {},
            }
            try self.session.journal.onTurnCompleted();
            self.is_player_turn = false;
        }
    } else {
        var itr = self.session.registry.query3(c.EnemyState, c.Initiative, c.Speed);
        while (itr.next()) |tuple| {
            const npc, const state, const initiative, const speed = tuple;
            _ = state;
            if (speed.move_points > initiative.move_points) continue;

            const action = self.session.ai.action(npc);
            _ = try self.doTurn(npc, action);
        }
        self.is_player_turn = true;
    }
    try self.updateQuickActions();
}

fn setTarget(self: *PlayMode, target: g.Entity) void {
    log.debug("Change target from {any} to {any}", .{ self.target, target });
    self.target = target;
    self.quick_actions.reset();
}

pub fn doTurn(self: *PlayMode, actor: g.Entity, action: g.actions.Action) !?g.actions.Action {
    log.info("The turn of the entity {d}.", .{actor.id});
    defer log.info("The end of the turn of entity {d}\n--------------------", .{actor.id});

    // Do Actions
    const actual_action, const mp = try self.session.actions.doAction(actor, action);
    log.info("Entity {d} spent {d} move points", .{ actor.id, mp });
    if (mp == 0) return actual_action;

    // Handle Initiative
    if (self.is_player_turn) {
        try self.session.events.sendEvent(.{ .player_turn_completed = .{ .spent_move_points = mp } });
        var itr = self.session.registry.query(c.Initiative);
        while (itr.next()) |tuple| {
            tuple[1].move_points += mp;
        }
    } else {
        const initiative = self.session.registry.get(actor, c.Initiative) orelse {
            log.err("The entity {d} doesn't have initiative.", .{actor.id});
            return error.NotEnoughComponents;
        };
        std.debug.assert(0 < mp and mp <= initiative.move_points);
        initiative.move_points -= mp;
    }
    return actual_action;
}

fn handleInput(self: *PlayMode) !?g.actions.Action {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        if (self.quick_actions_window) |*window| {
            if (try window.handleButton(btn)) {
                try window.hide(self.session.render, .from_buffer);
                window.deinit(self.arena.allocator());
                self.quick_actions_window = null;
            }
            switch (btn.game_button) {
                .a => return self.quickAction(),
                .up, .down => try window.draw(self.session.render),
                else => {},
            }
        } else {
            switch (btn.game_button) {
                .a => switch (btn.state) {
                    .released => return self.quickAction(),
                    .hold => {
                        self.quick_actions_window = try self.windowWithQuickActions();
                        try self.quick_actions_window.?.draw(self.session.render);
                        return null;
                    },
                },
                .b => switch (btn.state) {
                    .released => {
                        try self.session.lookAround();
                        // we have to handle changing the state right after this function
                        return null;
                    },
                    .hold => {
                        try self.session.explore();
                        // we have to handle changing the state right after this function
                        return null;
                    },
                },
                .left, .right, .up, .down => {
                    return g.actions.Action{
                        .move = .{
                            .target = .{ .direction = btn.toDirection().? },
                            .keep_moving = false,
                        },
                    };
                },
            }
        }
    }
    if (self.session.runtime.popCheat()) |cheat| {
        log.info("Run cheat {any}", .{cheat});
        switch (cheat) {
            .dump_entity => |entity| {
                const components = try self.session.registry.entityToStruct(entity);
                log.info("Components of the entity {d}:\n{f}", .{ entity.id, components });
            },
            .dump_vector_field => g.utils.DijkstraMap.dumpToLog(
                self.session.level.dijkstra_map,
                self.session.viewport.region,
            ),
            .turn_light_on => g.visibility.turn_light_on = true,
            .turn_light_off => g.visibility.turn_light_on = false,
            .set_health => |hp| {
                if (self.session.registry.get(self.session.player, c.Health)) |health| {
                    health.current = hp;
                }
            },
            .recognize => |entity| {
                if (g.meta.isEnemy(&self.session.registry, entity)) |enemy_type| {
                    try self.session.journal.markEnemyAsKnown(enemy_type);
                } else if (g.meta.isPotion(&self.session.registry, entity)) |potion_type| {
                    try self.session.journal.markPotionAsKnown(potion_type);
                } else {
                    try self.session.journal.markWeaponAsKnown(entity);
                }
            },
            else => if (try cheat.toAction(self.session)) |action| {
                return action;
            },
        }
    }
    return null;
}

/// If returns true then the input should be ignored
/// until all frames from all blocked animations will be drawn.
fn draw(self: *const PlayMode) !bool {
    var was_blocked_animation = false;
    if (self.quick_actions_window == null) {
        const level = &self.session.level;
        try self.session.render.drawDungeon(self.session.viewport, level);
        try self.session.render.drawSpritesToBuffer(self.session.viewport, level, self.target);
        was_blocked_animation = try self.drawAnimationsFrames();
        try self.session.render.drawChangedSymbols();
        try self.drawInfoBar();
    }
    return was_blocked_animation;
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
/// Returns true if one of animation is blocked.
pub fn drawAnimationsFrames(self: PlayMode) !bool {
    const now: c_uint = self.session.runtime.currentMillis();
    var was_blocked_animation: bool = false;
    var itr = self.session.level.registry.query2(c.Position, c.Animation);
    while (itr.next()) |components| {
        const entity, const position, const animation = components;
        was_blocked_animation |= animation.is_blocked;
        if (animation.frame(now)) |frame| {
            if (frame > 0 and self.session.viewport.region.containsPoint(position.place)) {
                const mode: g.DrawingMode = if (entity.eql(self.target))
                    .inverted
                else
                    .normal;
                try self.session.render.drawSpriteToBuffer(
                    self.session.viewport,
                    frame,
                    position.place,
                    3, // animations have max z order
                    mode,
                    self.session.level.checkVisibility(position.place),
                );
            }
        } else {
            try self.session.level.registry.remove(entity, c.Animation);
        }
    }
    return was_blocked_animation;
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.session.registry.get(self.session.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    try self.session.render.drawLeftButton("Explore", true);
    const qa = self.quickAction();
    const action_label = qa.toString();
    try self.session.render.drawRightButton(action_label, self.quick_actions.actions.items.len > 1);

    // Draw the name or health of the target entity
    if (self.target) |entity| {
        if (!entity.eql(self.session.player)) {
            if (self.session.registry.get2(entity, c.Sprite, c.Health)) |tuple| {
                try self.session.render.drawEnemyHealth(tuple[0].codepoint, tuple[1]);
                return;
            }
        }
        var buf: [32]u8 = undefined;
        try self.session.render.drawInfo(try g.descriptions.printName(&buf, self.session.journal, entity));
    } else {
        try self.session.render.cleanInfo();
    }
}

fn quickAction(self: PlayMode) g.actions.Action {
    if (self.quick_actions.actions.items.len > 0)
        return self.quick_actions.actions.items[self.quick_actions.selected_idx]
    else
        return .wait;
}

/// Checks that a target is exists and recalculates a list of available quick actions applicable to the target.
pub fn updateQuickActions(self: *PlayMode) anyerror!void {
    defer {
        log.debug(
            "{d} quick actions after update:\n{any}\nThe selected action is {any}\nThe target is {any}",
            .{
                self.quick_actions.actions.items.len,
                g.utils.toStringWithListOf(self.quick_actions.actions.items),
                self.quickAction(),
                self.target,
            },
        );
    }

    const alloc = self.arena.allocator();
    const selected_action = self.quickAction();
    log.debug(
        "Updating selected actions. Current selected action is {any}; target is {any}",
        .{ selected_action, self.target },
    );
    self.quick_actions.reset();

    // validate the target
    if (self.target) |target| {
        if (!self.session.registry.contains(target)) {
            log.debug("Target entity {d} was removed. Reset target.", .{target.id});
            self.target = null;
        }
    }

    // actualize and calculate quick actions for the target
    var itr = TargetsIterator.init(self.target, self.session);
    while (itr.next()) |target| {
        self.target = target;
        log.debug("New target {d}", .{target.id});
        if (self.session.actions.calculateQuickActionForTarget(target)) |qa| {
            log.debug("Calculated action is {any}", .{qa});
            try self.quick_actions.actions.append(alloc, qa);
            if (qa.eql(selected_action)) {
                self.quick_actions.selected_idx = self.quick_actions.actions.items.len - 1;
            }
            break;
        }
        log.debug("No quick action for entity {any}", .{target});
        self.target = null;
    }
    // player should always be able to manage its inventory...
    try self.quick_actions.actions.append(alloc, .wait);
    // ...and wait
    try self.quick_actions.actions.append(alloc, .open_inventory);
}

const TargetsIterator = struct {
    curren_target: ?g.Entity,
    player: g.Entity,
    player_position: *const c.Position,
    query: g.ecs.ArraySet(c.Position).Iterator,

    fn init(curren_target: ?g.Entity, session: *g.GameSession) TargetsIterator {
        return .{
            .player = session.player,
            .player_position = session.level.playerPosition(),
            .curren_target = curren_target,
            .query = session.registry.query(c.Position),
        };
    }

    fn next(self: *TargetsIterator) ?g.Entity {
        if (self.curren_target) |target| {
            self.curren_target = null;
            return target;
        } else {
            while (self.query.next()) |tuple| {
                const entity: g.Entity, const position: *c.Position = tuple;
                if (position.place.near4(self.player_position.place)) {
                    if (entity.eql(self.player)) {
                        continue;
                    } else {
                        return entity;
                    }
                }
            }
        }
        return null;
    }
};

fn windowWithQuickActions(self: *PlayMode) !w.ModalWindow(w.OptionsArea(void)) {
    var area = w.OptionsArea(void).center(self);
    for (self.quick_actions.actions.items, 0..) |qa, idx| {
        try area.addOption(self.arena.allocator(), qa.toString(), {}, chooseEntity, null);
        if (idx == self.quick_actions.selected_idx)
            try area.selectLine(idx);
    }
    return .default(area);
}

fn chooseEntity(ptr: *anyopaque, line_idx: usize, _: void) anyerror!void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    self.quick_actions.selected_idx = line_idx;
    log.debug("Choosen option {d}: {t}", .{ line_idx, self.quickAction() });
}
