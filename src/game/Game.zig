const std = @import("std");
const g = @import("game_pkg.zig");

const log = std.log.scoped(.Game);

const Game = @This();

pub const State = enum { welcome, game_over, game };

/// The general purpose allocator
gpa: std.mem.Allocator,
/// Playdate or terminal
runtime: g.Runtime,
/// Buffered render to draw the game
render: g.Render,
/// The seed is used to generate a new game session.
/// This seed can be used to pass the value from the user.
seed: u64,
/// The current state of the game
state: State,
/// The current game session
game_session: g.GameSession,

pub fn init(self: *Game, gpa: std.mem.Allocator, runtime: g.Runtime, seed: u64) !void {
    self.* = .{
        .gpa = gpa,
        .runtime = runtime,
        .render = undefined,
        .seed = seed,
        .state = .welcome,
        .game_session = undefined,
    };
    try self.render.init(gpa, runtime, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);
    try self.welcome();
}

pub fn deinit(self: *Game) void {
    self.render.deinit();
    if (self.state == .game)
        self.game_session.deinit();
}

pub fn tick(self: *Game) !void {
    switch (self.state) {
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) try self.newGame(),
                else => {},
            }
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) try self.welcome(),
                else => {},
            }
        },
        .game => {
            try self.game_session.tick();
            if (self.game_session.is_game_over) try self.gameOver();
        },
    }
}

inline fn welcome(self: *Game) !void {
    self.state = .welcome;
    self.runtime.removeAllMenuItems();
    try self.render.drawWelcomeScreen();
}

inline fn newGame(self: *Game) !void {
    std.debug.assert(self.state != .game);
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    _ = self.runtime.addMenuItem("Explore lvl", self, exploreMenu);
    try self.game_session.init(
        self.gpa,
        self.seed,
        self.runtime,
        self.render,
    );
    self.state = .game;
}

fn gameOver(self: *Game) !void {
    std.debug.assert(self.state == .game);
    self.game_session.deinit();
    self.state = .game_over;
    try self.render.drawGameOverScreen();
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    std.debug.assert(self.state == .game);
    self.game_session.deinit();
    self.welcome() catch @panic("Error when the Game went to the '.welcome' state");
}

fn exploreMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    std.debug.assert(self.state == .game);
    self.game_session.explore() catch @panic("Error on switching to the Explore mode");
}
