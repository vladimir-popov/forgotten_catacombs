//! This is the main mode of the game in which player travels through the dungeons.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const QuickAction = struct {
    target: g.Entity,
    action: g.actions.Action,
    pub fn format(self: QuickAction, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("QuickAction: {s}; target {d}", .{ @tagName(self.action), self.target.id });
    }
};

arena: std.heap.ArenaAllocator,
session: *g.GameSession,
// The actions which can be applied to the entity in focus
quick_actions: std.ArrayListUnmanaged(QuickAction),
// The index of the quick action for the target entity
selected_action_idx: usize = 0,
is_player_turn: bool = true,
quick_actions_window: ?w.ModalWindow(w.OptionsArea(void)) = null,

pub fn init(
    self: *PlayMode,
    alloc: std.mem.Allocator,
    session: *g.GameSession,
) !void {
    log.debug("Init PlayMode", .{});
    self.* = .{
        .arena = std.heap.ArenaAllocator.init(alloc),
        .session = session,
        .quick_actions = .empty,
    };
    try self.updateQuickActions(null, null);
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
        try self.doTurn(self.session.player, action);
        self.is_player_turn = false;
    } else {
        var itr = self.session.entities.registry.query3(c.EnemyState, c.Initiative, c.Speed);
        while (itr.next()) |tuple| {
            const npc, const state, const initiative, const speed = tuple;
            _ = state;
            if (speed.move_points > initiative.move_points) continue;

            const action = self.session.ai.action(npc);
            try self.doTurn(npc, action);
        }
        self.is_player_turn = true;
    }
}

pub fn doTurn(self: *PlayMode, actor: g.Entity, action: g.actions.Action) !void {
    log.info("The turn of the entity {d}.", .{actor.id});
    defer log.info("The end of the turn of entity {d}\n--------------------", .{actor.id});

    // Handle Impacts
    if (try self.session.handleImpacts(actor)) {
        // actor is dead
        return;
    }

    // Do Actions
    const mp = try g.actions.doAction(self.session, actor, action);
    log.info("Entity {d} spent {d} move points", .{ actor.id, mp });
    if (mp == 0) return;

    // Handle Initiative
    if (self.is_player_turn) {
        log.debug("Update quick actions after action '{s}'", .{@tagName(action)});
        try self.updateQuickActions(self.target(), self.quickAction());
        var itr = self.session.entities.registry.query(c.Initiative);
        while (itr.next()) |tuple| {
            tuple[1].move_points += mp;
        }
    } else {
        const initiative = self.session.entities.registry.get(actor, c.Initiative) orelse {
            log.err("The entity {d} doesn't have initiative.", .{actor.id});
            return error.NotEnoughComponents;
        };
        std.debug.assert(0 < mp and mp <= initiative.move_points);
        initiative.move_points -= mp;
    }
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
                    .hold => if (self.quick_actions.items.len > 0) {
                        self.quick_actions_window =
                            try self.windowWithQuickActions(self.quick_actions.items, self.selected_action_idx);
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
            .dump_vector_field => g.utils.DijkstraMap.dumpToLog(
                self.session.level.dijkstra_map,
                self.session.viewport.region,
            ),
            .turn_light_on => g.visibility.turn_light_on = true,
            .turn_light_off => g.visibility.turn_light_on = false,
            .set_health => |hp| {
                if (self.session.entities.registry.get(self.session.player, c.Health)) |health| {
                    health.current = hp;
                }
            },
            else => if (cheat.toAction(self.session)) |action| {
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
        try self.session.render.drawSpritesToBuffer(self.session.viewport, level, self.target());
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
    var itr = self.session.level.entities.registry.query2(c.Position, c.Animation);
    while (itr.next()) |components| {
        const entity, const position, const animation = components;
        was_blocked_animation |= animation.is_blocked;
        if (animation.frame(now)) |frame| {
            if (frame > 0 and self.session.viewport.region.containsPoint(position.place)) {
                const mode: g.DrawingMode = if (entity.eql(self.target()))
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
            try self.session.level.entities.registry.remove(entity, c.Animation);
        }
    }
    return was_blocked_animation;
}

fn drawInfoBar(self: *const PlayMode) !void {
    if (self.session.entities.registry.get(self.session.player, c.Health)) |health| {
        try self.session.render.drawPlayerHp(health);
    }
    try self.session.render.drawLeftButton("Explore", true);
    const qa = self.quickAction();
    const action_label = qa.toString();
    try self.session.render.drawRightButton(action_label, self.quick_actions.items.len > 1);

    // Draw the name or health of the target entity
    if (self.target()) |entity| {
        if (!entity.eql(self.session.player)) {
            if (self.session.entities.registry.get2(entity, c.Sprite, c.Health)) |tuple| {
                try self.session.render.drawEnemyHealth(tuple[0].codepoint, tuple[1]);
                return;
            }
        }
        const name = if (self.session.entities.registry.get(entity, c.Description)) |desc| desc.name() else "?";
        try self.session.render.drawInfo(name);
    } else {
        try self.session.render.cleanInfo();
    }
}

fn target(self: PlayMode) ?g.Entity {
    return if (self.quick_actions.items.len == 0 or self.selected_action_idx > self.quick_actions.items.len - 1)
        null
    else if (self.quick_actions.items[self.selected_action_idx].action == .wait)
        null
    else
        self.quick_actions.items[self.selected_action_idx].target;
}

fn quickAction(self: PlayMode) g.actions.Action {
    return self.quick_actions.items[self.selected_action_idx].action;
}

pub fn updateQuickActions(self: *PlayMode, target_entity: ?g.Entity, prev_action: ?g.actions.Action) anyerror!void {
    defer {
        log.debug(
            "{d} quick actions after update:\n{any}The selected action is {any}\nThe previous was {any}",
            .{
                self.quick_actions.items.len,
                g.utils.toStringWithListOf(self.quick_actions.items),
                self.quickAction(),
                prev_action,
            },
        );
    }

    self.quick_actions.clearRetainingCapacity();
    self.selected_action_idx = 0;
    const alloc = self.arena.allocator();

    if (target_entity) |tg| {
        if (tg.id != self.session.player.id) {
            // check if quick action is available for target
            if (g.actions.calculateQuickActionForTarget(self.session, tg)) |qa| {
                self.selected_action_idx = self.quick_actions.items.len;
                try self.quick_actions.append(alloc, .{ .target = tg, .action = qa });
            }
        }
    }
    const player_position = self.session.level.playerPosition();
    // Check the nearest entities:
    // TODO improve:
    var itr = self.session.entities.registry.query(c.Position);
    while (itr.next()) |tuple| {
        const entity: g.Entity, const position: *c.Position = tuple;
        if (position.place.near4(player_position.place)) {
            if (entity.eql(self.session.player) or entity.eql(target_entity)) continue;
            log.debug(
                "The place {any} near the player {any} with {any}",
                .{ position.place, player_position.place, entity },
            );
            if (g.actions.calculateQuickActionForTarget(self.session, entity)) |qa| {
                log.debug("Calculated action is {any}", .{qa});
                if (qa.eql(prev_action)) {
                    self.selected_action_idx = self.quick_actions.items.len;
                }
                try self.quick_actions.append(alloc, .{ .target = entity, .action = qa });
            } else {
                log.debug("No quick action for entity {any}", .{entity});
            }
        }
    }
    // player should always be able to
    // wait
    try self.quick_actions.append(alloc, .{ .target = self.session.player, .action = .wait });
    // manage its inventory
    try self.quick_actions.append(alloc, .{ .target = self.session.player, .action = .open_inventory });
}

fn windowWithQuickActions(
    self: *PlayMode,
    variants: []const QuickAction,
    selected: usize,
) !w.ModalWindow(w.OptionsArea(void)) {
    var window = w.options(void, self);
    for (variants, 0..) |qa, idx| {
        try window.area.addOption(self.arena.allocator(), qa.action.toString(), {}, chooseEntity, null);
        if (idx == selected)
            try window.area.selectLine(idx);
    }
    return window;
}

fn chooseEntity(ptr: *anyopaque, line_idx: usize, _: void) anyerror!void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    self.selected_action_idx = line_idx;
    log.debug("Choosen option {d}: {s}", .{ line_idx, @tagName(self.quickAction()) });
}
