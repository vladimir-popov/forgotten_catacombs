//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.play_mode);

/// How long a notification should be shown by default
const SHOW_NOTIFICATION_MS = 700;

const Self = @This();

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

/// A notification about important event.
/// Should be show for some time.
const NotificationMessage = struct {
    /// the buffer for the text of the notification
    buffer: [20]u8 = undefined,
    len: u8 = 0,
    /// when the notification appears on a screen
    start_showing_at: u64,
    /// where to place the first latter of the notification
    pp: p.Point,
    /// which mode should be used to show the notification
    mode: g.DrawingMode,

    /// The region of the display occupied by the notification
    pub fn region(self: NotificationMessage) p.Region {
        return .{ .top_left = self.pp, .rows = 1, .cols = @intCast(self.len) };
    }

    /// Precalculates a notification message from a notification.
    /// Text, position and mode will be calculate once to show the message every tick for the whole delay.
    pub fn init(notification: g.notifications.Notification, session: *const g.GameSession) !NotificationMessage {
        var msg: NotificationMessage = .{
            // Start calculation of the place to show from the player place on the screen
            .pp = session.viewport.relative(session.level.playerPosition().place) orelse unreachable,
            .start_showing_at = session.runtime.currentMillis(),
            .mode = switch (notification) {
                .exp => .inverted,
                else => .normal,
            },
        };
        msg.len = @intCast((try std.fmt.bufPrint(&msg.buffer, "{f}", .{notification})).len);
        const display_region = p.Region.init(1, 1, session.viewport.region.rows, session.viewport.region.cols);

        // Trying to place the notification relative to the player in follow order:
        const relative_positions = [_]p.Direction{ .up, .down, .right, .left };
        for (relative_positions) |direction| {
            switch (direction) {
                .up, .down => {
                    const left_half: u8 = msg.len / 2;
                    msg.pp.move(direction);
                    // center the notification.
                    // validate left border
                    if (msg.pp.col > left_half)
                        msg.pp.col -= left_half
                    else if (left_half > msg.pp.col)
                        msg.pp.col = 1;
                    // validate right border
                    if (msg.pp.col + msg.len - 1 > display_region.cols)
                        msg.pp.col = display_region.cols - msg.len + 1;
                },
                .right => {
                    msg.pp.move(direction);
                },
                .left => {
                    msg.pp.moveNTimes(.left, msg.len);
                },
            }

            // The notification should not hide the current enemy (but it could be dead and removed at
            // this moment, for example, when we're showing a notification about receiving exp)
            const maybe_enemy_position = switch (notification) {
                .hit => |hit| session.registry.get(hit.target, c.Position),
                .damage => |damage| session.registry.get(damage.actor, c.Position),
                .miss => |miss| session.registry.get(miss.target, c.Position),
                .dodge => |dodge| session.registry.get(dodge.actor, c.Position),
                else => null,
            };
            const is_hide_the_target = if (maybe_enemy_position) |pos|
                if (session.viewport.relative(pos.place)) |enemy_pp|
                    msg.region().containsPoint(enemy_pp)
                else
                    false
            else
                false;
            const is_first_letter_on_screen = display_region.containsPoint(msg.pp);
            const is_last_letter_on_screen = display_region.containsPoint(msg.pp.movedToNTimes(.right, msg.len - 1));

            if (is_first_letter_on_screen and is_last_letter_on_screen and !is_hide_the_target) {
                // all done
                break;
            } else {
                // reset the point and try another direction
                msg.pp = session.viewport.relative(session.level.playerPosition().place) orelse unreachable;
            }
        }
        return msg;
    }
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
// The entity to which a quick actions can be applied
target: ?g.Entity = null,
quick_actions: QuickActions,
is_player_turn: bool = true,
quick_actions_window: ?w.ModalWindow(w.OptionsArea(void)) = null,
// If defined then all input should be ignored.
notification: ?NotificationMessage = null,

pub fn init(
    self: *Self,
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

pub fn deinit(self: Self) void {
    self.arena.deinit();
}

fn setTarget(self: *Self, target: g.Entity) void {
    log.debug("Change target from {any} to {any}", .{ self.target, target });
    self.target = target;
    self.quick_actions.reset();
}

/// Trying to do an action. Action can be changed, or ignored.
/// For example, moving can lead to a collision with an enemy, or with a wall. In first case the
/// action will be changed to `hit` and completely ignored in another.
/// Returns an actual action and a count of spent move points.
/// When action requires more move points than initiative, the `error.NotEnoughMovePoints` will be
/// returned.
pub fn doTurn(
    self: *Self,
    actor: g.Entity,
    action: g.actions.Action,
    initiative: g.MovePoints,
) !struct { ?g.Action, g.MovePoints } {
    log.info("The turn of the entity {d}.", .{actor.id});
    defer log.info("The end of the turn of entity {d}\n--------------------", .{actor.id});

    // Do Actions
    const actual_action, const mp = try self.session.actions.doAction(actor, action, initiative);
    log.info("Entity {d} spent {d} move points", .{ actor.id, mp });

    // Handle Initiative
    if (self.is_player_turn and mp > 0) {
        // Add initiative points to enemies
        var itr = self.session.registry.query(c.Initiative);
        while (itr.next()) |tuple| {
            tuple[1].move_points += mp;
        }
        try self.session.events.sendEvent(.{ .player_turn_completed = .{ .spent_move_points = mp } });
    }
    return .{ actual_action, mp };
}

fn handleInput(self: *Self) !?g.actions.Action {
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
                if (g.meta.getEnemyType(&self.session.registry, entity)) |enemy_type| {
                    try self.session.journal.markEnemyAsKnown(enemy_type);
                } else if (g.meta.getPotionType(&self.session.registry, entity)) |potion_type| {
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

pub fn tick(self: *Self) !void {
    if (try self.draw()) return;

    if (self.is_player_turn) {
        // break this function if no input
        const action = (try self.handleInput()) orelse return;
        const tuple = try self.doTurn(self.session.player, action, std.math.maxInt(g.MovePoints));
        if (tuple[0]) |actual_action| {
            // Force change the target
            switch (actual_action) {
                .hit => |enemy| {
                    self.setTarget(enemy);
                },
                .open => |door| {
                    self.setTarget(door.id);
                },
                else => {},
            }
            // Update counters of unknown equipments
            try self.session.journal.onTurnCompleted();
            self.is_player_turn = false;
        }
    } else {
        var itr = self.session.registry.query(c.Initiative);
        while (itr.next()) |tuple| {
            const npc, const initiative = tuple;
            loop: while (true) {
                // TODO: compare initiative with minimal required mp to prevent calculating an action
                const action = self.session.ai.action(npc);
                const actual_action, const mp = self.doTurn(npc, action, initiative.move_points) catch |err| {
                    switch (err) {
                        error.NotEnoughMovePoints => break :loop,
                        else => return err,
                    }
                };
                g.utils.assert(
                    mp <= initiative.move_points,
                    "Entity {d} spent more MP {d} than initiative has {any}. Actin was {any}",
                    .{ npc.id, mp, initiative, actual_action },
                );
                initiative.move_points -= mp;
            }
        }
        self.is_player_turn = true;
    }
    try self.updateQuickActions();
}

/// If returns true then the input should be ignored
/// until all notifications and all frames from all blocked animations will be drawn.
fn draw(self: *Self) !bool {
    if (self.quick_actions_window == null) {
        try self.drawInfoBar();
        const level = &self.session.level;
        try self.session.render.drawDungeonToBuffer(self.session.viewport, level);
        try self.session.render.drawSpritesToBuffer(self.session.viewport, level, self.target);
        const blocked_animation = try self.drawAnimationsFramesToBuffer();
        try self.session.render.drawChangedSymbols();
        const notification_shown = try self.showNotifications();
        if (self.session.registry.get(self.session.player, c.Health)) |health| {
            try self.session.render.drawPlayerHp(health);
        }
        if (blocked_animation or notification_shown) {
            try self.session.runtime.cleanInputBuffer();
            return true;
        }
    }
    return false;
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
/// Returns true if one of animation is blocked.
pub fn drawAnimationsFramesToBuffer(self: Self) !bool {
    const now: u64 = self.session.runtime.currentMillis();
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

fn showNotifications(self: *Self) !bool {
    if (self.notification) |msg| {
        if (self.session.runtime.currentMillis() - msg.start_showing_at > SHOW_NOTIFICATION_MS) {
            try self.session.render.redrawRegionFromSceneBuffer(msg.region());
            self.notification = null;
            return false;
        } else {
            try self.session.render.drawText(msg.buffer[0..msg.len], msg.pp, msg.mode);
            // try self.session.render.drawInfo(msg.buffer[0..msg.len]);
            return true;
        }
    }
    if (self.session.notifications.popFront()) |notification| {
        self.notification = try .init(notification, self.session);
        return true;
    }
    return false;
}

fn drawInfoBar(self: *const Self) !void {
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
    } else if (self.session.registry.get(self.session.player, c.Hunger)) |hunger| {
        // Draw the hunger level
        switch (hunger.level()) {
            .well_fed => try self.session.render.cleanInfo(),
            else => |lvl| {
                var buf: [g.Render.INFO_ZONE_LENGTH]u8 = undefined;
                try self.session.render.drawInfo(try std.fmt.bufPrint(&buf, "{f}", .{lvl}));
            },
        }
    } else {
        try self.session.render.cleanInfo();
    }
}

fn quickAction(self: Self) g.actions.Action {
    if (self.quick_actions.actions.items.len > 0)
        return self.quick_actions.actions.items[self.quick_actions.selected_idx]
    else
        return .wait;
}

/// Checks that a target is exists and recalculates a list of available quick actions applicable to the target.
pub fn updateQuickActions(self: *Self) anyerror!void {
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
    // Remember the previously selected action to trying to keep it selected
    const selected_action = self.quickAction();
    log.debug(
        "Updating selected actions. Current selected action is {any}; target is {any}",
        .{ selected_action, self.target },
    );
    self.quick_actions.reset();

    // validate the current target
    if (self.target) |target| {
        if (!self.session.registry.contains(target)) {
            log.debug("Target entity {d} was removed. Reset the target.", .{target.id});
            self.target = null;
        }
    }

    const player_position = self.session.level.playerPosition();

    // Actualize and calculate quick actions for the target if it's defined,
    // or find another
    const player_weapon = g.meta.getWeapon(&self.session.registry, self.session.player)[1];
    // iterate over all possible targets starting from the current
    var itr = TargetsIterator.init(self.target, self.session, player_position);
    while (itr.next()) |target| {
        self.target = target;
        log.debug("New target {d}", .{target.id});
        if (self.session.actions.calculateQuickActionForTarget(player_position.place, player_weapon, target)) |qa| {
            log.debug("Calculated action is {any}", .{qa});
            try self.quick_actions.actions.append(alloc, qa);
            if (qa.eql(selected_action)) {
                self.quick_actions.selected_idx = self.quick_actions.actions.items.len - 1;
            }
            // Compare action priorities to choose the most important target
            else if (qa.priority() > self.quickAction().priority()) {
                self.target = target;
                self.quick_actions.selected_idx = self.quick_actions.actions.items.len - 1;
            }
            break;
        }
        log.debug("No quick action for entity {any}", .{target});
        self.target = null;
    }

    // TODO: Move to the iterator
    // Entities under the player's feet should be included to possible actions
    const cell_under_feet = self.session.level.cellAt(player_position.place);
    switch (cell_under_feet) {
        .entities => |entities| {
            for (0..2) |i| {
                if (entities[i]) |entity| {
                    const maybe_action = self.session.actions.calculateQuickActionForTarget(
                        player_position.place,
                        player_weapon,
                        entity,
                    );
                    if (maybe_action) |qa| {
                        try self.quick_actions.actions.append(alloc, qa);
                        // Compare action priorities to choose the most important target
                        if (qa.priority() > self.quickAction().priority()) {
                            self.target = entity;
                            self.quick_actions.selected_idx = self.quick_actions.actions.items.len - 1;
                        }
                    }
                }
            }
        },
        else => {},
    }

    // player should always be able to wait...
    try self.quick_actions.actions.append(alloc, .wait);
    // ...and  manage its inventory.
    try self.quick_actions.actions.append(alloc, .open_inventory);
}

/// Iterates over all entities with `Position` component on the level,
/// except entities under the player's feet.
const TargetsIterator = struct {
    curren_target: ?g.Entity,
    player: g.Entity,
    player_position: *const c.Position,
    query: g.ecs.ArraySet(c.Position).Iterator,

    fn init(curren_target: ?g.Entity, session: *g.GameSession, player_position: *const c.Position) TargetsIterator {
        return .{
            .player = session.player,
            .player_position = player_position,
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
                    if (position.place.eql(self.player_position.place)) {
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

fn windowWithQuickActions(self: *Self) !w.ModalWindow(w.OptionsArea(void)) {
    var area = w.OptionsArea(void).center(self);
    for (self.quick_actions.actions.items, 0..) |qa, idx| {
        try area.addOption(self.arena.allocator(), qa.toString(), {}, chooseEntity, null);
        if (idx == self.quick_actions.selected_idx)
            try area.selectLine(idx);
    }
    return .default(area);
}

fn chooseEntity(ptr: *anyopaque, line_idx: usize, _: void) anyerror!void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.quick_actions.selected_idx = line_idx;
    log.debug("Choosen option {d}: {t}", .{ line_idx, self.quickAction() });
}
