//! This is the main mode of the game in which player travel through the dungeons.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;

const AI = @import("AI.zig");
const ActionSystem = @import("ActionSystem.zig");
const CollisionSystem = @import("CollisionSystem.zig");
const DamageSystem = @import("DamageSystem.zig");

const log = std.log.scoped(.play_mode);

const PlayMode = @This();

const System = *const fn (play_mode: *PlayMode) anyerror!void;

const Enemies = struct {
    const MovePoints = u8;

    const Enemy = struct {
        entity: g.Entity,
        move_points: u8,
    };

    session: *g.GameSession,
    /// Dynamically changed dictionary of the enemies, which is updated every tick,
    /// but is not cleaned after the player's move.
    enemies: std.AutoHashMap(g.Entity, MovePoints),
    /// The index of all enemies, which are potentially can perform an action.
    /// This list recreated every player's move.
    not_completed: std.DoublyLinkedList(g.Entity),
    /// Arena for the `not_completed` list
    arena: *std.heap.ArenaAllocator,
    /// The pointer to the next enemy, which should perform an action.
    next_enemy: ?*std.DoublyLinkedList(g.Entity).Node = null,

    fn init(alloc: std.mem.Allocator, session: *g.GameSession) !Enemies {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        return .{
            .session = session,
            .enemies = std.AutoHashMap(g.Entity, MovePoints).init(alloc),
            .arena = arena,
            .not_completed = std.DoublyLinkedList(g.Entity){},
        };
    }

    fn deinit(self: *Enemies) void {
        self.enemies.deinit();
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    fn resetNotCompleted(self: *Enemies) !void {
        _ = self.arena.reset(.retain_capacity);
        self.not_completed = std.DoublyLinkedList(g.Entity){};
        self.next_enemy = null;
    }

    fn addMovePoints(self: *Enemies, entity: g.Entity, move_points: u8) !void {
        var node = try self.arena.allocator().create(std.DoublyLinkedList(g.Entity).Node);
        node.data = entity;
        self.not_completed.append(node);

        const gop = try self.enemies.getOrPut(entity);
        if (gop.found_existing) {
            gop.value_ptr.* +|= move_points;
        } else {
            gop.value_ptr.* = move_points;
        }
    }

    inline fn removeMovePoints(self: *Enemies, entity: g.Entity, move_points: u8) void {
        if (self.enemies.getPtr(entity)) |mp| {
            mp.* -|= move_points;
        }
    }

    inline fn completeMove(self: *Enemies, entity: g.Entity) void {
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
    fn next(self: *Enemies) ?Enemy {
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
            if (self.enemies.get(enemy)) |move_points| {
                if (self.session.level.components.getForEntity(enemy, c.NPC)) |_| {
                    return .{ .entity = enemy, .move_points = move_points };
                } else {
                    log.debug("It looks like the entity {d} was removed. Remove it from enemies", .{enemy});
                    _ = self.enemies.remove(enemy);
                    self.completeMove(enemy);
                }
            }
        }
        return null;
    }
};

session: *g.GameSession,
enemies: Enemies,
/// Highlighted entity
entity_in_focus: ?g.Entity,
// An action which could be applied to the entity in focus
quick_action: ?c.Action,

pub fn init(session: *g.GameSession, alloc: std.mem.Allocator) !PlayMode {
    return .{
        .session = session,
        .enemies = try Enemies.init(alloc, session),
        .entity_in_focus = null,
        .quick_action = null,
    };
}

pub fn deinit(self: PlayMode) void {
    self.enemies.deinit();
}

/// Updates the target entity after switching back to the play mode
pub fn refresh(self: *PlayMode, entity_in_focus: ?g.Entity) !void {
    self.entity_in_focus = entity_in_focus;
    if (entity_in_focus) |ef| if (ef == self.session.level.player) {
        self.entity_in_focus = null;
    };
    try self.updateTarget();
    try self.session.render.redraw(self.session, self.entity_in_focus);
}

fn handleInput(self: *PlayMode, button: g.Button) !void {
    if (button.state == .double_pressed) log.debug("Double press of {any}", .{button});
    switch (button.game_button) {
        .a => if (self.quick_action) |action| {
            try self.session.level.components.setToEntity(self.session.level.player, action);
        },
        .b => if (button.state == .pressed) {
            try self.session.explore();
        },
        .left, .right, .up, .down => {
            const speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            try self.session.level.components.setToEntity(self.session.level.player, c.Action{
                .type = .{
                    .move = .{
                        .target = .{ .direction = button.toDirection().? },
                        .keep_moving = false, // btn.state == .double_pressed,
                    },
                },
                .move_points = speed.move_points,
            });
        },
        .cheat => {
            if (self.session.runtime.getCheat()) |cheat| {
                log.debug("Cheat {any}", .{cheat});
                if (cheat.toAction(self.session)) |action| {
                    try self.session.level.components.setToEntity(self.session.level.player, action);
                }
            }
        },
    }
}

pub fn tick(self: *PlayMode) anyerror!void {
    try self.session.render.drawScene(self.session, self.entity_in_focus);
    if (self.session.level.components.getAll(c.Animation).len > 0)
        return;

    try self.session.render.drawQuickActionButton(self.quick_action);
    // we should update target only if the player did some action at this tick
    var should_update_target: bool = false;

    // the list of enemies is empty at the start
    if (self.enemies.next()) |enemy| {
        const action = AI.action(self.session, enemy.entity);
        if (action.move_points > enemy.move_points) {
            log.debug(
                "Not enough move points to perform action '{s}' by the entity {d}. It has only {d} mp, but required {d}.",
                .{ @tagName(action.type), enemy.entity, enemy.move_points, action.move_points },
            );
            self.enemies.completeMove(enemy.entity);
        } else {
            self.enemies.removeMovePoints(enemy.entity, enemy.move_points);
            try self.session.level.components.setToEntity(enemy.entity, action);
        }
    } else if (try self.session.runtime.readPushedButtons()) |buttons| {
        try self.handleInput(buttons);
        // break this function if the mode was changed
        if (self.session.mode != .play) return;
        // If the player did some action
        if (self.session.level.components.getForEntity(self.session.level.player, c.Action)) |action| {
            should_update_target = true;
            // every action shout take some amount of points
            std.debug.assert(action.move_points > 0);
            // find all enemies and give them move points
            try self.addMovePointsToEnemies(action.move_points);
        }
    }
    try self.runSystems();
    if (should_update_target) try self.updateTarget();
}

/// Collect NPC and set them move points
fn addMovePointsToEnemies(self: *PlayMode, move_points: u8) !void {
    try self.enemies.resetNotCompleted();
    var itr = self.session.level.query().get(c.NPC);
    while (itr.next()) |tuple| {
        try self.enemies.addMovePoints(tuple[0], move_points);
    }
}

fn runSystems(self: *PlayMode) !void {
    try ActionSystem.doActions(self.session);
    try CollisionSystem.handleCollisions(self.session);
    // collision could lead to new actions
    // if the player had collision with enemy, that enemy should appear in focus
    if (self.session.level.components.getForEntity(self.session.level.player, c.Action)) |action| {
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
    try DamageSystem.handleDamage(self.session);
}

fn updateTarget(self: *PlayMode) anyerror!void {
    defer {
        const qa_str = if (self.quick_action) |qa| @tagName(qa.type) else "not defined";
        log.debug("Entity in focus {any}; quick action {s}", .{ self.entity_in_focus, qa_str });
    }

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
    self.quick_action = .{
        .type = .wait,
        .move_points = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed).move_points,
    };
}

fn calculateQuickActionForTarget(
    self: PlayMode,
    target: g.Entity,
) ?c.Action {
    const player_position = self.session.level.playerPosition();
    const target_position = self.session.level.components.getForEntity(target, c.Position) orelse return null;
    if (player_position.point.near(target_position.point)) {
        if (self.session.level.components.getForEntity(target, c.Ladder)) |ladder| {
            // the player should be able to go between levels only from the
            // place with the ladder
            if (!player_position.point.eql(target_position.point)) return null;
            // It's impossible to go upper the first level
            if (ladder.direction == .up and self.session.level.depth == 0) return null;

            const player_speed = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            return .{ .type = .{ .move_to_level = ladder.* }, .move_points = player_speed.move_points };
        }
        if (self.session.level.components.getForEntity(target, c.Health)) |_| {
            const weapon = self.session.level.components.getForEntityUnsafe(self.session.level.player, c.MeleeWeapon);
            return .{
                .type = .{ .hit = target },
                .move_points = weapon.move_points,
            };
        }
        if (self.session.level.components.getForEntity(target, c.Door)) |door| {
            // the player should not be able to open/close the door stay in the doorway
            if (player_position.point.eql(target_position.point)) {
                return null;
            }
            const player_speed =
                self.session.level.components.getForEntityUnsafe(self.session.level.player, c.Speed);
            return switch (door.state) {
                .opened => .{ .type = .{ .close = target }, .move_points = player_speed.move_points },
                .closed => .{ .type = .{ .open = target }, .move_points = player_speed.move_points },
            };
        }
    }
    return null;
}
