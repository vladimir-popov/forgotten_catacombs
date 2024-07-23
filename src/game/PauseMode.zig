const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const Render = @import("Render.zig");

const log = std.log.scoped(.pause_mode);

const PauseMode = @This();

session: *game.GameSession,
arena: std.heap.ArenaAllocator,
alloc: std.mem.Allocator,
target: *Node,

pub fn create(session: *game.GameSession) !*PauseMode {
    const self = try session.runtime.alloc.create(PauseMode);
    self.session = session;
    self.arena = std.heap.ArenaAllocator.init(session.runtime.alloc);
    self.alloc = self.arena.allocator();
    self.target = try self.alloc.create(Node);
    return self;
}

pub fn destroy(self: *PauseMode) void {
    self.arena.deinit();
    self.session.runtime.alloc.destroy(self);
}

pub fn clear(self: *PauseMode) void {
    _ = self.arena.reset(.free_all);
}

pub fn refresh(self: *PauseMode) !void {
    self.target.* = Node{
        .entity = self.session.player,
        .position = self.session.components.getForEntityUnsafe(self.session.player, game.Position).point,
    };
    var itr = self.session.query.get(game.Position);
    while (itr.next()) |tuple| {
        if (tuple[0] != self.session.player and self.session.screen.region.containsPoint(tuple[1].point)) {
            const node = try self.alloc.create(Node);
            node.* = .{ .entity = tuple[0], .position = tuple[1].point };
            self.target.add(node);
        }
    }
}

pub fn tick(self: *PauseMode) anyerror!void {
    // Nothing should happened until the player pushes a button
    if (try self.session.runtime.readPushedButtons()) |btn| {
        switch (btn.code) {
            game.Buttons.A => {},
            game.Buttons.B => {
                self.session.play();
                return;
            },
            game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
                self.chooseNextEntity(btn.toDirection().?);
            },
            else => {},
        }
    }
    // rendering should be independent on input,
    // to be able to play animations
    try Render.render(self.session);
}

pub fn draw(self: PauseMode) !void {
    try self.session.runtime.drawLabel("pause", .{ .row = 1, .col = game.DISPLAY_DUNG_COLS + 2 });
    // highlight entity in focus
    if (self.session.components.getForEntity(self.target.entity, game.Sprite)) |target_sprite| {
        const position = self.session.components.getForEntityUnsafe(self.target.entity, game.Position);
        try self.session.runtime.drawSprite(&self.session.screen, target_sprite, position, .inverted);
    }
    if (self.session.components.getForEntity(self.target.entity, game.Description)) |description| {
        try Render.drawEntityName(self.session, description.name);
    }
    if (self.session.components.getForEntity(self.target.entity, game.Health)) |hp| {
        try Render.drawEnemyHP(self.session, hp);
    }
}

fn chooseNextEntity(self: *PauseMode, direction: p.Direction) void {
    self.target = switch (direction) {
        .up => self.target.top,
        .down => self.target.bottom,
        .left => self.target.left,
        .right => self.target.right,
    } orelse self.target;
}

const Node = struct {
    entity: game.Entity,
    position: p.Point,

    left: ?*Node = null,
    right: ?*Node = null,
    top: ?*Node = null,
    bottom: ?*Node = null,

    fn add(self: *Node, other: *Node) void {
        if (self.position.row < other.position.row)
            self.addBottom(other);
        if (self.position.row > other.position.row)
            self.addOnTop(other);
        if (self.position.col > other.position.col)
            self.addLeft(other);
        if (self.position.col < other.position.col)
            self.addRight(other);
    }

    fn addOnTop(self: *Node, other: *Node) void {
        if (self.top) |self_top| {
            if (self_top.position.row < other.position.row) {
                self_top.addOnTop(other);
            } else {
                other.addOnTop(self_top);
                self.top = other;
                other.bottom = self;
            }
        } else {
            self.top = other;
            other.bottom = self;
        }
    }

    fn addBottom(self: *Node, other: *Node) void {
        if (self.bottom) |self_bottom| {
            if (self_bottom.position.row > other.position.row) {
                self_bottom.addBottom(other);
            } else {
                other.addBottom(self_bottom);
                self.bottom = other;
                other.top = self;
            }
        } else {
            self.bottom = other;
            other.top = self;
        }
    }

    fn addLeft(self: *Node, other: *Node) void {
        if (self.left) |self_left| {
            if (self_left.position.col > other.position.col) {
                self_left.addLeft(other);
            } else {
                other.addLeft(self_left);
                self.left = other;
                other.right = self;
            }
        } else {
            self.left = other;
            other.right = self;
        }
    }

    fn addRight(self: *Node, other: *Node) void {
        if (self.right) |self_right| {
            if (self_right.position.col < other.position.col) {
                self_right.addRight(other);
            } else {
                other.addRight(self_right);
                self.right = other;
                other.left = self;
            }
        } else {
            self.right = other;
            other.left = self;
        }
    }
};
