const std = @import("std");
const g = @import("game_pkg.zig");

const log = std.log.scoped(.Game);

const Game = @This();

pub const State = enum { welcome, game_over, game };

/// Playdate or terminal
runtime: g.Runtime,
/// Module to draw the game
render: g.Render,
/// The seed is used to generate a new game session.
/// This seed can be used to pass the value from the user.
seed: u64,
/// The current state of the game
state: State,
/// The current game session
game_session: ?*g.GameSession,
///
events: g.events.EventBus,

pub fn init(runtime: g.Runtime, seed: u64) !*Game {
    var self = try runtime.alloc.create(Game);
    self.* = .{
        .runtime = runtime,
        .render = g.Render.init(runtime),
        .seed = seed,
        .state = .welcome,
        .game_session = null,
        .events = g.events.EventBus.init(runtime.alloc),
    };
    try self.events.subscribeOn(g.events.EntityMoved, self.render.viewport.subscriber());
    try self.welcome();
    return self;
}

pub fn destroy(self: *Game) void {
    if (self.game_session) |session| session.destroy();
    self.events.deinit();
    self.runtime.alloc.destroy(self);
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    self.welcome() catch @panic("Error when the Game went to the '.welcome' state");
}

pub fn tick(self: *Game) !void {
    switch (self.state) {
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .pressed) try self.newGame(),
                else => {},
            }
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .pressed) try self.welcome(),
                else => {},
            }
        },
        .game => if (self.game_session) |session| try session.tick(),
    }
}

inline fn welcome(self: *Game) !void {
    self.state = .welcome;
    self.runtime.removeAllMenuItems();
    try self.render.drawWelcomeScreen();
}

inline fn newGame(self: *Game) !void {
    self.state = .game;
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    if (self.game_session) |game_session| {
        game_session.destroy();
        self.game_session = null;
    }
    self.game_session = try g.GameSession.createNew(self, self.seed);
    try self.game_session.?.play(null);
}

pub fn gameOver(self: *Game) !void {
    self.state = .game_over;
    try self.render.drawGameOverScreen();
}
