const std = @import("std");
const game = @import("game.zig");
const algs = @import("algs_and_types");
const p = algs.primitives;

const Render = @import("Render.zig");

const log = std.log.scoped(.pause_mode);

const PauseMode = @This();

session: *game.GameSession,
entities_on_screen: std.AutoHashMap(p.Point, game.Entity),
target: game.Entity,

pub fn init(session: *game.GameSession) !PauseMode {
    var entities = std.AutoHashMap(p.Point, game.Entity).init(session.runtime.alloc);
    // TODO improve
    var itr = session.entities.iterator();
    while (itr.next()) |entity| {
        if (session.components.getForEntity(entity.*, game.Sprite)) |s| {
            if (session.screen.region.containsPoint(s.position))
                try entities.put(s.position, entity.*);
        }
    }
    return .{
        .session = session,
        .target = session.player,
        .entities_on_screen = entities,
    };
}

pub fn deinit(self: *PauseMode) void {
    self.entities_on_screen.deinit();
}

pub fn handleInput(self: *PauseMode, buttons: game.Buttons) !void {
    switch (buttons.code) {
        game.Buttons.A => {},
        game.Buttons.B => {
            self.session.play();
        },
        game.Buttons.Left, game.Buttons.Right, game.Buttons.Up, game.Buttons.Down => {
            self.chooseNextEntity(buttons.toDirection().?);
        },
        else => {},
    }
}

pub fn draw(self: PauseMode) !void {
    try self.session.runtime.drawLabel("pause", .{ .row = 1, .col = game.DISPLAY_DUNG_COLS + 2 });
    try highlightEntityInFocus(self.session, self.target);
    if (self.session.components.getForEntity(self.target, game.Description)) |description| {
        try Render.drawEntityName(self.session, description.name);
    }
    if (self.session.components.getForEntity(self.target, game.Health)) |hp| {
        try Render.drawEnemyHP(self.session, hp);
    }
}

fn highlightEntityInFocus(session: *const game.GameSession, entity: game.Entity) !void {
    if (session.components.getForEntity(entity, game.Sprite)) |target_sprite| {
        try session.runtime.drawSprite(&session.screen, target_sprite, .inverted);
    }
}

fn chooseNextEntity(pause_mode: *PauseMode, direction: p.Direction) void {
    const session = pause_mode.session;
    const init_position = session.components.getForEntity(pause_mode.target, game.Sprite).?.position;
    var itr = Iterator.init(init_position, direction, session.screen.region);
    while (itr.next()) |position| {
        if (pause_mode.entities_on_screen.get(position)) |entity| {
            pause_mode.target = entity;
            return;
        }
    }
}

/// Iterates over points in follow way:
///      0
///    3 1 2
///  7 5 4 6 8
const Iterator = struct {
    init_position: p.Point,
    current_position: p.Point,
    direction: p.Direction,
    region: p.Region,
    side_direction: p.Direction,
    distance: u8 = 1,
    d: u8 = 0,

    fn init(init_position: p.Point, direction: p.Direction, region: p.Region) Iterator {
        return .{
            .init_position = init_position,
            .current_position = init_position,
            .direction = direction,
            .side_direction = direction.rotatedClockwise(true),
            .region = region,
        };
    }

    fn next(self: *Iterator) ?p.Point {
        if (self.d == 0) {
            self.current_position = self.init_position;
            self.current_position.moveNTimes(self.direction, self.distance);
            self.d += 1;
        } else {
            self.current_position.moveNTimes(self.side_direction, self.d);
            self.side_direction = self.side_direction.opposite();
            self.d += 1;
        }
        if (self.d > self.distance * 2) {
            self.distance += 1;
            self.d = 0;
        }
        if (self.region.containsPoint(self.current_position)) return self.current_position else return null;
    }
};

test Iterator {
    // given:
    var itr = Iterator.init(
        .{ .row = 1, .col = 3 },
        .down,
        .{ .top_left = .{ .row = 1, .col = 1 }, .rows = 3, .cols = 5 },
    );
    var result = std.ArrayList(p.Point).init(std.testing.allocator);
    defer result.deinit();
    // when:
    while (itr.next()) |point| {
        try result.append(point);
    }
    // then:
    const expected: [8]p.Point = .{
        p.Point{ .row = 2, .col = 2 },
        p.Point{ .row = 2, .col = 3 },
        p.Point{ .row = 2, .col = 4 },
        p.Point{ .row = 3, .col = 1 },
        p.Point{ .row = 3, .col = 2 },
        p.Point{ .row = 3, .col = 3 },
        p.Point{ .row = 3, .col = 4 },
        p.Point{ .row = 3, .col = 5 },
    };
    std.mem.sort(p.Point, result.items, {}, lessThan);
    try std.testing.expectEqualSlices(p.Point, &expected, result.items);
}
fn lessThan(_: void, x: p.Point, y: p.Point) bool {
    if (x.row < y.row) return true;
    if (x.row > y.row) return false;
    return x.col < y.col;
}
