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
game_session: ?*g.GameSession = null,
game_session_arena: std.heap.ArenaAllocator,
///
events: *g.events.EventBus = undefined,
events_arena: std.heap.ArenaAllocator,

pub fn create(alloc: std.mem.Allocator, runtime: g.Runtime, seed: u64) !*Game {
    var self = try alloc.create(Game);
    self.* = .{
        .alloc = alloc,
        .runtime = runtime,
        .render = try g.Render.init(
            alloc,
            runtime,
            g.DISPLAY_ROWS - 2,
            g.DISPLAY_COLS,
        ),
        .seed = seed,
        .state = .welcome,
        .game_session_arena = std.heap.ArenaAllocator.init(alloc),
        .events_arena = std.heap.ArenaAllocator.init(alloc),
    };
    self.events = try g.events.EventBus.create(&self.events_arena);
    try self.events.subscribe(self.subscriber());
    try self.events.subscribe(self.render.viewport.subscriber());
    try self.welcome();
    return self;
}

pub fn destroy(self: *Game) void {
    self.game_session_arena.deinit();
    self.events_arena.deinit();
    self.render.deinit();
    self.alloc.destroy(self);
}

inline fn welcome(self: *Game) !void {
    self.state = .welcome;
    self.runtime.removeAllMenuItems();
    try self.render.drawWelcomeScreen();
}

inline fn newGame(self: *Game) !void {
    self.state = .game;
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    _ = self.runtime.addMenuItem("Explore lvl", self, exploreMenu);
    if (self.game_session) |gs| {
        gs.unsubscribe();
    }
    _ = self.game_session_arena.reset(.retain_capacity);
    self.game_session = try g.GameSession.create(
        &self.game_session_arena,
        self.seed,
        self.runtime,
        &self.render,
        self.events,
    );
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    self.welcome() catch @panic("Error when the Game went to the '.welcome' state");
}

fn exploreMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    self.game_session.?.explore() catch @panic("Error on looking around");
}

pub fn subscriber(self: *Game) g.events.Subscriber {
    return .{ .context = self, .onEvent = gameOver };
}

pub fn gameOver(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *Game = @ptrCast(@alignCast(ptr));
    switch (event) {
        .entity_died => |entity_died| {
            if (entity_died.is_player) {
                _ = self.game_session_arena.reset(.retain_capacity);
                self.state = .game_over;
                try self.render.drawGameOverScreen();
            }
        },
        else => {},
    }
}

pub fn tick(self: *Game) !void {
    switch (self.state) {
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .pressed) try self.newGame(),
                .cheat => _ = self.runtime.getCheat(),
                else => {},
            }
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .pressed) try self.welcome(),
                .cheat => _ = self.runtime.getCheat(),
                else => {},
            }
        },
        .game => try self.game_session.?.tick(),
    }
    try self.events.notifySubscribers();
}
