//! This is the main mode of the game in which player travel through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const ActionSystem = @import("ActionSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const EnemiesIterator = struct {
    /// The GameSession has a pointer to the actual level
    session: *g.GameSession,
    /// The index of all enemies, which are potentially can perform an action.
    /// This list recreated every player's move.
    not_completed: std.DoublyLinkedList(g.Entity),
    /// Arena for the `not_completed` list
    arena: *std.heap.ArenaAllocator,
    /// The pointer to the next enemy, which should perform an action.
    next_enemy: ?*std.DoublyLinkedList(g.Entity).Node = null,

    fn init(alloc: std.mem.Allocator, session: *g.GameSession) !EnemiesIterator {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        return .{
            .session = session,
            .arena = arena,
            .not_completed = std.DoublyLinkedList(g.Entity){},
        };
    }

    fn deinit(self: *EnemiesIterator) void {
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    fn resetNotCompleted(self: *EnemiesIterator) !void {
        _ = self.arena.reset(.retain_capacity);
        self.not_completed = std.DoublyLinkedList(g.Entity){};
        self.next_enemy = null;
    }

    /// Collects NPC and adds them move points
    fn addMovePoints(self: *EnemiesIterator, move_points: u8) !void {
        try self.resetNotCompleted();
        var itr = self.session.level.query().get(c.Initiative);
        while (itr.next()) |tuple| {
            var node = try self.arena.allocator().create(std.DoublyLinkedList(g.Entity).Node);
            node.data = tuple[0];
            tuple[1].move_points +|= move_points;
            self.not_completed.append(node);
        }
    }

    inline fn completeMove(self: *EnemiesIterator, entity: g.Entity) void {
        var itr = self.not_completed.first;
        while (itr) |node| {
            if (node.data == entity) {
                const updated_current = if (node == self.next_enemy) node.next else self.next_enemy;
                self.not_completed.remove(node);
                self.next_enemy = updated_current;
                return;
            } else {
                itr = node.next;
            }
        }
    }

    /// Returns the enemies circle back, till all of them complete their moves
    fn next(self: *EnemiesIterator) ?struct { g.Entity, *c.Initiative, *c.Position, *c.Speed } {
        if (self.next_enemy == null) {
            self.next_enemy = self.not_completed.first;
        }
        while (self.next_enemy) |current_enemy| {
            const enemy = current_enemy.data;
            if (current_enemy.next) |next_enemy| {
                self.next_enemy = next_enemy;
            } else {
                self.next_enemy = self.not_completed.first;
            }
            if (self.session.level.components.getForEntity3(enemy, c.Initiative, c.Position, c.Speed)) |res| {
                return res;
            } else {
                log.debug("It looks like the entity {d} was removed. Remove it from enemies", .{enemy});
                self.completeMove(enemy);
            }
        }
        return null;
    }
};

session: *g.GameSession,
enemies: EnemiesIterator,
ai: g.AI,
/// Highlighted entity
entity_in_focus: ?g.Entity,
// An action which could be applied to the entity in focus
quick_action: ?g.Action,

pub fn init(session: *g.GameSession, alloc: std.mem.Allocator, rand: std.Random) !PlayMode {
    log.debug("Init PlayMode", .{});
    return .{
        .session = session,
        .enemies = try EnemiesIterator.init(alloc, session),
        .ai = g.AI{ .session = session, .rand = rand },
        .entity_in_focus = null,
        .quick_action = null,
    };
}

pub fn deinit(self: PlayMode) void {
    self.enemies.deinit();
}

/// Updates the target entity after switching back to the play mode
pub fn update(self: *PlayMode, entity_in_focus: ?g.Entity) !void {
    self.entity_in_focus = entity_in_focus;
    if (entity_in_focus) |ef| if (ef == self.session.level.player) {
        self.entity_in_focus = null;
    };
    log.debug("Update target after refresh", .{});
    try self.updateTarget();
    try self.session.render.redraw(self.session, self.entity_in_focus, self.quick_action);
}

pub fn subscriber(self: *PlayMode) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *PlayMode = @ptrCast(@alignCast(ptr));
    switch (event) {
        .player_hit => {
            self.entity_in_focus = event.player_hit.target;
            log.debug("Update target after player hit", .{});
            try self.updateTarget();
        },
        // TODO: Move to level
        .entity_moved => |entity_moved| if (entity_moved.entity == self.session.level.player) {
            try self.session.level.onPlayerMoved(entity_moved);
        },
        else => {},
    }
}

fn handleInput(self: *PlayMode, button: g.Button) !?g.Action {
    if (button.state == .double_pressed) log.debug("Double press of {any}", .{button});
    switch (button.game_button) {
        .a => if (self.quick_action) |action| {
            return action;
        },
        .b => if (button.state == .pressed) {
            try self.session.lookAround();
            // we have to handle changing the state right after this function
            return null;
        },
        .left, .right, .up, .down => {
            return g.Action{
                .move = .{
                    .target = .{ .direction = button.toDirection().? },
                    .keep_moving = false, // btn.state == .double_pressed,
                },
            };
        },
        .cheat => {
            if (self.session.runtime.getCheat()) |cheat| {
                log.debug("Cheat {any}", .{cheat});
                switch (cheat) {
                    .dump_vector_field => self.session.level.dijkstra_map.dumpToLog(),
                    .turn_light_on => g.visibility.turn_light_on = true,
                    .turn_light_off => g.visibility.turn_light_on = false,
                    else => if (cheat.toAction(self.session)) |action| {
                        return action;
                    },
                }
            }
        },
    }
    return null;
}

pub fn tick(self: *PlayMode) !void {
    try self.session.render.drawScene(self.session, self.entity_in_focus, self.quick_action);
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return;

    // the list of enemies is empty at the start
    if (self.enemies.next()) |tuple| {
        const entity = tuple[0];
        const initiative = tuple[1];
        const position = tuple[2];
        const speed = tuple[3];
        if (speed.move_points > initiative.move_points) {
            self.enemies.completeMove(entity);
            return;
        }
        const action = self.ai.action(entity, position.point);
        const mp = try ActionSystem.doAction(self.session, entity, action, speed.move_points);
        std.debug.assert(0 < mp and mp <= initiative.move_points);
        tuple[1].move_points -= mp;
    } else if (try self.session.runtime.readPushedButtons()) |buttons| {
        const maybe_action = try self.handleInput(buttons);
        // break this function if the mode was changed
        if (self.session.mode != .play) return;
        // If the player did some action
        if (maybe_action) |action| {
            const speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            const mp = try ActionSystem.doAction(self.session, self.session.level.player, action, speed.move_points);
            if (mp > 0) {
                log.debug("Update target after action {any}", .{action});
                try self.updateTarget();
                // find all enemies and give them move points
                try self.enemies.addMovePoints(mp);
            }
        }
    }
}

fn updateTarget(self: *PlayMode) anyerror!void {
    defer {
        const qa_str = if (self.quick_action) |qa| @tagName(qa) else "not defined";
        log.debug("Entity in focus after update {any}; quick action {s}", .{ self.entity_in_focus, qa_str });
    }
    log.debug("Update target. Current entity in focus is {any}", .{self.entity_in_focus});

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
    self.quick_action = .wait;
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target: g.Entity,
) ?g.Action {
    const player_position = self.session.level.playerPosition();
    const target_position = self.session.level.components.getForEntity(target, c.Position) orelse return null;
    if (player_position.point.near(target_position.point)) {
        if (self.session.level.components.getForEntity(target, c.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with the ladder
            if (!player_position.point.eql(target_position.point)) return null;
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            return .{ .move_to_level = ladder.* };
        }
        if (self.session.level.components.getForEntity(self.session.level.player, c.Weapon)) |weapon| {
            if (self.session.level.components.getForEntity(target, c.Health)) |health| {
                return .{ .hit = .{ .target = target, .target_health = health, .by_weapon = weapon } };
            }
        }
        if (self.session.level.components.getForEntity(target, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            return switch (door.state) {
                .opened => .{ .close = target },
                .closed => .{ .open = target },
            };
        }
    }
    return null;
}
