//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.play_mode);

/// How long a notification should be shown by default
const SHOW_NOTIFICATION_MS = 800;

const Self = @This();

session: *g.GameSession,
// The entity to which quick actions can be applied
target: ?g.Entity = null,
quick_actions: QuickActions,
is_players_turn: bool = true,
quick_actions_window: ?w.ModalWindow(w.OptionsArea(void)) = null,
// If defined, then all input should be ignored.
notification_to_show: ?NotificationMessage = null,

pub fn init(
    self: *Self,
    session: *g.GameSession,
    target: ?g.Entity,
) !void {
    log.debug("Init PlayMode. Target is {any}", .{target});
    self.* = .{
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

inline fn setTarget(self: *Self, target: ?g.Entity) void {
    log.debug("Change target from {any} to {any}", .{ self.target, target });
    self.target = target;
    self.quick_actions.reset();
}

pub fn tick(self: *Self) !void {
    // TODO draw only after changes and return 1, else 0.
    if (try self.isDrawing()) {
        try self.session.runtime.cleanInputBuffer();
        // skip getting an input from the player, or AI actions to show blocking animations
        // and pop-up notifications
        return;
    }

    if (self.is_players_turn) {
        try self.playerTurn();
    } else {
        try self.enemiesTurn();
    }
    try self.updateQuickActions();
}

fn playerTurn(self: *Self) !void {
    // break this function if no input
    var action = (try self.handleInput()) orelse return;
    const action_result = try self.doTurn(self.session.player, &action, std.math.maxInt(g.MovePoints));
    switch (action_result) {
        .done => {
            // Force change the target
            switch (action.tag) {
                .hit => {
                    const enemy = action.payload.hit;
                    if (self.session.registry.contains(enemy)) {
                        self.setTarget(enemy);
                    } else {
                        self.setTarget(null);
                    }
                },
                .open => {
                    const door = action.payload.open;
                    self.setTarget(door.id);
                },
                else => {},
            }
            self.is_players_turn = false;
        },
        else => {},
    }
}

fn enemiesTurn(self: *Self) !void {
    log.debug("enemiesTurn {d}", .{self.session.runtime.stackSize()});
    var itr = self.session.registry.query(c.Initiative);
    while (itr.next()) |tuple| {
        const npc, const initiative = tuple;
        // repeat doing something until move points are over
        loop: while (true) {
            // TODO: compare initiative with minimal required mp to prevent calculating an action
            var action = self.session.ai.action(npc);
            const action_result = try self.doTurn(npc, &action, initiative.move_points);
            switch (action_result) {
                .repeat_action_handler => continue :loop,
                .done => |mp| {
                    g.utils.assert(
                        mp <= initiative.move_points,
                        "Entity {d} spent more MP {d} than initiative has {any}.",
                        .{ npc.id, mp, initiative },
                    );
                    initiative.move_points -= mp;
                },
                .not_enough_points, .actor_is_dead => break :loop,
                .declined => {},
            }
        }
    }
    self.is_players_turn = true;
}

/// Draws the whole screen.
///
/// Returns true if the drawing is not completed,
/// and the input should be ignored.
fn isDrawing(self: *Self) !bool {
    // the quick_actions_window is drawn during handleInput
    if (self.quick_actions_window != null) return false;

    try self.drawInfoBar();
    const level = &self.session.level;
    try self.session.render.drawDungeonToBuffer(self.session.viewport, level);
    try self.session.render.drawEntitiesToBuffer(
        self.session.viewport,
        &self.session.journal,
        self.session.prng.random(),
        level,
        self.target,
    );
    const now = self.session.runtime.currentMillis();
    const is_blocked_animation = try self.drawAnimationsFramesToBuffer(now);

    // Flash all scene changes to display
    try self.session.render.drawChangedSymbols();

    // Draw pop-up notifications
    const notification_shown = try self.showNotifications(now);

    // Draw player's hp
    try self.session.render.drawPlayerHp(self.session.registry.getUnsafe(self.session.player, c.Health));

    return is_blocked_animation or notification_shown;
}

/// Draws a single frame from every animation.
/// Removes the animation if the last frame was drawn.
/// Returns true if any animation is blocked.
pub fn drawAnimationsFramesToBuffer(self: *const Self, now: u64) !bool {
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
                    self.session.level.checkPlaceVisibility(position.place),
                );
            }
        } else {
            try self.session.level.registry.remove(entity, c.Animation);
        }
    }
    return was_blocked_animation;
}

/// Draws the `notification_to_show` if it's defined.
/// if more time from start of showing has passed than `SHOW_NOTIFICATION_MS`, removed the `notification_to_show`,
/// and tries to get a next notification from the global queue.
///
/// Returns `true` if a notification should be keep showed.
fn showNotifications(self: *Self, now: u64) !bool {
    if (self.notification_to_show) |notification| {
        if (now - notification.start_showing_at < SHOW_NOTIFICATION_MS) {
            // Show the notification
            try self.session.render.drawText(notification.buffer[0..notification.len], notification.pp, .inverted);
            return true;
        } else {
            // Hide the notification after timeout
            try self.session.render.redrawRegionFromSceneBuffer(notification.region());
            self.notification_to_show = null;
        }
    }
    if (self.session.notifications.popFront()) |notification| {
        // Get a next notification
        self.notification_to_show = try NotificationMessage.init(notification, self.session);
        // We should not wait a next invocation, because it requires an input and can happened too late.
        try self.session.render.drawText(
            self.notification_to_show.?.buffer[0..self.notification_to_show.?.len],
            self.notification_to_show.?.pp,
            .inverted,
        );
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
        try self.session.render.drawInfo(try g.meta.printActualName(&buf, self.session.journal, entity));
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

// NOTE: the quick_actions_window can be drawn during this method
fn handleInput(self: *Self) !?g.actions.Action {
    if (try self.session.runtime.readPushedButtons()) |btn| {
        log.debug("handleInput {d}", .{self.session.runtime.stackSize()});
        if (self.quick_actions_window) |*window| {
            if (try window.handleButton(btn)) {
                try window.hide(self.session.render, .from_buffer);
                window.deinit(self.session.mode_arena.allocator());
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
                    return .action(.move, .{ .target = .{ .direction = btn.toDirection().? } });
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
            .get_item => |item| {
                const entity = try self.session.registry.addNewEntity(g.entities.presets.Items.get(item));
                try self.session.registry.getUnsafe(self.session.player, c.Inventory).items.add(entity);
            },
            .turn_light_on => g.visibility.turn_light_on = true,
            .turn_light_off => g.visibility.turn_light_on = false,
            .level_up => |new_level| {
                const level_before = self.session.registry.getUnsafe(self.session.player, c.Experience).level;
                if (new_level > level_before) {
                    const exp = g.meta.Levels[new_level - 1];
                    _ = try g.meta.addExperience(&self.session.registry, self.session.player, exp);
                }
            },
            .set_experience => |exp| {
                _ = try g.meta.addExperience(&self.session.registry, self.session.player, exp);
            },
            .set_health => |hp| {
                if (self.session.registry.get(self.session.player, c.Health)) |health| {
                    health.current_hp = hp;
                }
            },
            .set_money => |money| {
                self.session.registry.getUnsafe(self.session.player, c.Wallet).money = money;
            },
            .recognize => |entity| {
                if (g.meta.getEnemyType(&self.session.registry, entity)) |enemy_type| {
                    try self.session.journal.markEnemyAsKnown(enemy_type);
                } else if (g.meta.getPotionType(&self.session.registry, entity)) |potion_type| {
                    try self.session.journal.markPotionAsKnown(potion_type);
                } else if (self.session.registry.has(entity, c.Weapon)) {
                    try self.session.journal.markWeaponAsKnown(entity);
                } else if (self.session.registry.has(entity, c.Protection)) {
                    try self.session.journal.markArmorAsKnown(entity);
                }
            },
            else => if (try cheat.toAction(self.session)) |action| {
                return action;
            },
        }
    }
    return null;
}

/// Trying to do an action. The action can be changed or ignored.
/// For example, the `move` action can lead to a collision with an enemy or a wall. In the first case,
/// the action will be changed to `hit`, and completely ignored (changed to `do_nothing`) in the second.
///
/// It returns result of handling the action. In successful case the actual count of spent move
/// points is stored in the result.
/// When an action requires more move points than initiative, `error.NotEnoughMovePoints` will be
/// returned.
pub fn doTurn(
    self: *Self,
    actor: g.Entity,
    action: *g.actions.Action,
    initiative: g.MovePoints,
) !g.actions.ActionResult {
    log.info("The turn of the entity {d}.", .{actor.id});
    defer log.info("The end of the turn of entity {d}\n--------------------", .{actor.id});

    log.debug("doTurn {d}", .{self.session.runtime.stackSize()});
    const move_points_for_action = g.meta.movePointsForAction(&self.session.registry, actor, action);
    if (move_points_for_action > initiative)
        return .not_enough_points;

    // Do Actions
    loop: while (true) {
        const action_result = try self.session.actions.doAction(actor, action, move_points_for_action);
        switch (action_result) {
            .repeat_action_handler => continue :loop,
            .done => |mp| {
                log.info("Entity {d} spent {d} move points", .{ actor.id, mp });

                // Handle Initiative
                if (self.is_players_turn and mp > 0) {
                    // Add initiative points to enemies
                    var itr = self.session.registry.query(c.Initiative);
                    while (itr.next()) |tuple| {
                        tuple[1].move_points += mp;
                    }
                    try self.session.sendEvent(.{ .player_turn_completed = .{ .spent_move_points = mp } });
                }
            },
            .actor_is_dead => {
                log.info("Entity {d} is dead after action {t}", .{ actor.id, action.tag });
            },
            .not_enough_points => {
                log.debug("Entity {d} has not enough move points for action {t}", .{ actor.id, action.tag });
            },
            .declined => {
                log.debug("The action {t} was declined for the entity {d}", .{ action.tag, actor.id });
            },
        }
        return action_result;
    }
}

fn quickAction(self: *const Self) g.actions.Action {
    if (self.quick_actions.actions.items.len > 0)
        return self.quick_actions.actions.items[self.quick_actions.selected_idx]
    else
        return .action(.wait, {});
}

/// Checks that the target exists, or finds another.
/// Recalculates the list of available quick actions applicable to the target.
pub fn updateQuickActions(self: *Self) anyerror!void {
    defer {
        if (g.utils.isDebug())
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
    log.debug("updateQActions {d}", .{self.session.runtime.stackSize()});

    const alloc = self.session.mode_arena.allocator();
    // Remember the previously selected action to try to keep it selected
    const prev_selected_action = self.quickAction();
    log.debug(
        "Updating selected actions. Current selected action is {any}; target is {any}",
        .{ prev_selected_action, self.target },
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
    // Iterate through all valid targets, skipping entities located at the same position as the player,
    // starting from the current target.
    var itr = TargetsIterator.init(self.target, self.session, player_position);
    while (itr.next()) |target| {
        self.target = target;
        log.debug("New target {d}", .{target.id});
        if (self.session.actions.calculateQuickActionForTarget(player_position.place, player_weapon, target)) |qa| {
            log.debug("Calculated action is {any}", .{qa});
            try self.quick_actions.actions.append(alloc, qa);
            // Try to keep previous selection
            if (qa.tag == prev_selected_action.tag) {
                self.quick_actions.selected_idx = self.quick_actions.actions.items.len - 1;
            }
            // Let's use the first target with calculated qa.
            // It makes impossible to choose the best possible action, but it's more effective
            // and not so terrible.
            break;
        }
        log.debug("No quick action for entity {any}", .{target});
        self.target = null;
    }

    // Entities under the player's feet should be additionally included in the possible actions
    const cell_under_feet = self.session.level.cellAt(player_position.place);
    switch (cell_under_feet) {
        .entities => |entities| {
            for (c.Position.ZOrder.indexes) |i| {
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

    // The player should always be able to wait...
    try self.quick_actions.actions.append(alloc, .action(.wait, {}));
    // ...and manage its inventory.
    try self.quick_actions.actions.append(alloc, .action(.open_inventory, {}));
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

/// Builds a window with quick actions list
fn windowWithQuickActions(self: *Self) !w.ModalWindow(w.OptionsArea(void)) {
    var area = w.OptionsArea(void).centered(self);
    for (self.quick_actions.actions.items, 0..) |qa, idx| {
        try area.addOption(self.session.mode_arena.allocator(), qa.toString(), {}, chooseQuickAction, null);
        if (idx == self.quick_actions.selected_idx)
            try area.selectLine(idx);
    }
    return .defaultModalWindow(area);
}

/// Sets the index of the current quick action to the currently selected item in the window
fn chooseQuickAction(ptr: *anyopaque, line_idx: usize, _: void) anyerror!bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    self.quick_actions.selected_idx = line_idx;
    log.debug("Chosen option {d}: {t}", .{ line_idx, self.quickAction().tag });
    return true;
}

pub const QuickActions = struct {
    // The actions which can be applied to the entity in focus
    actions: std.ArrayList(g.actions.Action) = .empty,
    // The index of the quick action for the target entity
    selected_idx: usize = 0,

    fn reset(self: *QuickActions) void {
        self.actions.clearRetainingCapacity();
        self.selected_idx = 0;
    }
};

/// A notification about important event.
/// Should be shown for some time.
const NotificationMessage = struct {
    /// the buffer for the text of the notification
    buffer: [16]u8 = undefined,
    len: u8 = 0,
    /// when the notification appears on a screen
    start_showing_at: u64,
    /// where to place the first letter of the notification
    pp: p.Point,

    /// The region of the display occupied by the notification
    pub fn region(self: NotificationMessage) p.Region {
        return .{ .top_left = self.pp, .rows = 1, .cols = @intCast(self.len) };
    }

    /// Precalculates a notification message from a notification.
    /// Text, position and mode will be calculated once to show the message every tick for the whole delay.
    pub fn init(notification: g.notifications.Notification, session: *const g.GameSession) !NotificationMessage {
        var msg: NotificationMessage = .{
            // Start calculation of the place to show from the player place on the screen
            .pp = session.viewport.relative(session.level.playerPosition().place) orelse unreachable,
            .start_showing_at = session.runtime.currentMillis(),
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
            const is_hiding_the_target = if (maybe_enemy_position) |pos|
                if (session.viewport.relative(pos.place)) |enemy_pp|
                    msg.region().containsPoint(enemy_pp)
                else
                    false
            else
                false;
            const is_first_letter_on_screen = display_region.containsPoint(msg.pp);
            const is_last_letter_on_screen = display_region.containsPoint(msg.pp.movedToNTimes(.right, msg.len - 1));

            if (is_first_letter_on_screen and is_last_letter_on_screen and !is_hiding_the_target) {
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
