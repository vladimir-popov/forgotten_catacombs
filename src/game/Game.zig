const std = @import("std");
const g = @import("game_pkg.zig");

const log = std.log.scoped(.Game);

const Game = @This();

pub const State = enum { welcome, game_over, game };

alloc: std.mem.Allocator,
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
game_session: g.GameSession = undefined,
game_session_arena: std.heap.ArenaAllocator,
///
events: g.events.EventBus,

pub fn create(alloc: std.mem.Allocator, runtime: g.Runtime, seed: u64) !*Game {
    var self = try alloc.create(Game);
    self.* = .{
        .alloc = alloc,
        .runtime = runtime,
        .render = try g.Render.init(alloc, runtime, g.Level.isVisible),
        .seed = seed,
        .state = .welcome,
        .game_session_arena = std.heap.ArenaAllocator.init(alloc),
        .events = try g.events.EventBus.init(alloc),
    };
    try self.welcome();
    return self;
}

pub fn destroy(self: *Game) void {
    self.game_session_arena.deinit();
    self.events.deinit();
    self.render.deinit();
    self.alloc.destroy(self);
}

inline fn welcome(self: *Game) !void {
    _ = self.game_session_arena.reset(.retain_capacity);
    self.state = .welcome;
    self.runtime.removeAllMenuItems();
    try self.render.drawWelcomeScreen();
}

inline fn newGame(self: *Game) !void {
    self.state = .game;
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    try self.game_session.initNew(
        self.game_session_arena.allocator(),
        self.seed,
        self.runtime,
        self.render,
        self.events,
    );
    try self.game_session.play(null);
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    self.welcome() catch @panic("Error when the Game went to the '.welcome' state");
}

pub fn gameOver(self: *Game) !void {
    if (self.state == .game) self.game_session.deinit();
    self.state = .game_over;
    try self.render.drawGameOverScreen();
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
        .game => try self.game_session.tick(),
    }
}
