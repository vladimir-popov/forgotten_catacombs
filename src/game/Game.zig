const std = @import("std");
const g = @import("game_pkg.zig");

const log = std.log.scoped(.Game);

const Game = @This();

pub const State = union(enum) {
    welcome,
    game_over,
    game_session: *g.GameSession,

    fn deinit(self: *State) void {
        if (self.* == .game_session) {
            self.game_session.destroy();
        }
    }
};

pub const TickResult = enum { continue_game, player_dead, player_win };

alloc: std.mem.Allocator,
/// This prng is used to make any dynamic decision by AI, or game events,
/// but not to generate any level objects.
prng: std.Random.DefaultPrng,
/// Playdate or terminal
runtime: g.Runtime,
/// Module to draw the game
render: g.Render,
/// The seed is used to generate a new game session.
/// This seed can be used to pass the value from the user.
seed: u64,
/// The current state of the game
state: State,

pub fn create(alloc: std.mem.Allocator, runtime: g.Runtime, seed: u64) !*Game {
    var self = try alloc.create(Game);
    self.* = .{
        .alloc = alloc,
        .prng = std.Random.DefaultPrng.init(seed),
        .runtime = runtime,
        .render = try g.Render.init(
            alloc,
            runtime,
            g.DISPLAY_ROWS - 2,
            g.DISPLAY_COLS,
        ),
        .seed = seed,
        .state = .welcome,
    };
    try self.render.drawWelcomeScreen();
    return self;
}

pub fn destroy(self: *Game) void {
    self.state.deinit();
    self.render.deinit();
    self.alloc.destroy(self);
}

pub fn subscriber(self: *Game) g.events.Subscriber {
    return .{ .context = self, .onEvent = handleEvent };
}

fn handleEvent(ptr: *anyopaque, event: g.events.Event) !void {
    const self: *Game = @ptrCast(@alignCast(ptr));
    if (self.state == .game_session) {
        try self.state.game_session.handleEvent(self.state.game_session, event);
    }
    switch (event) {
        .entity_died => |entity_died| {
            if (entity_died.is_player) {
                self.state.game_session.destroy();
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
                .a => if (btn.state == .released) {
                    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
                    _ = self.runtime.addMenuItem("Explore lvl", self, exploreMenu);

                    self.state = .{ .game_session = try g.GameSession.create(
                        self.alloc,
                        self.seed,
                        self.prng.random(),
                        self.runtime,
                        &self.render,
                    ) };
                },
                else => {},
            }
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) {
                    self.state = .welcome;
                    self.runtime.removeAllMenuItems();
                    try self.render.drawWelcomeScreen();
                },
                else => {},
            }
        },
        .game_session => |game_session| switch (try game_session.tick()) {
            .player_dead => {
                self.state.game_session.destroy();
                self.state = .game_over;
                try self.render.drawGameOverScreen();
            },
            else => {},
        },
    }
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    if (self.state == .game_session)
        self.state.game_session.destroy();

    self.state = .welcome;
    self.runtime.removeAllMenuItems();
    self.render.drawWelcomeScreen() catch @panic("Error on drawing Welcome screen");
}

fn exploreMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Game = @ptrCast(@alignCast(ptr.?));
    switch (self.state) {
        .game_session => |game_session| game_session.explore() catch @panic("Error on looking around"),
        else => {},
    }
}
