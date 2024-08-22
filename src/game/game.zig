const std = @import("std");
const ecs = @import("ecs");

pub usingnamespace @import("components.zig");

pub const AnyRuntime = @import("AnyRuntime.zig");
pub const Render = @import("Render.zig");
pub const Buttons = @import("Buttons.zig");

pub const Entity = ecs.Entity;
pub const Screen = @import("Screen.zig");
pub const Dungeon = @import("BspDungeon.zig").BspDungeon(WHOLE_DUNG_ROWS, WHOLE_DUNG_COLS);
// pub const Dungeon = @import("BspDungeon.zig").BspDungeon(DISPLPAY_ROWS, DISPLPAY_COLS);

pub const GameSession = @import("GameSession.zig");

/// The maximum rows count in the whole dungeon
pub const WHOLE_DUNG_ROWS: u8 = 40;
/// The maximum columns count in the whole dungeon
pub const WHOLE_DUNG_COLS: u8 = 100;

pub const RENDER_DELAY_MS = 150;

// Playdate display resolution px:
pub const DISPLAY_HEIGHT = 240;
pub const DISPLAY_WIDHT = 400;

// The size of the font to draw sprites in pixels:
pub const SPRITE_HEIGHT = 20;
pub const SPRITE_WIDTH = 10;

// The size of the font for text in pixels:
pub const FONT_HEIGHT = 16;
pub const FONT_WIDTH = 8;

pub const DISPLAY_ROWS = DISPLAY_HEIGHT / SPRITE_HEIGHT - 1;
pub const DISPLAY_COLS = DISPLAY_WIDHT / SPRITE_WIDTH - 1;

pub const DOUBLE_PUSH_DELAY_MS = 250;
pub const HOLD_DELAY_MS = 500;

pub const Game = struct {
    pub const State = enum { welcome, game_over, game };

    /// Playdate or terminal
    runtime: AnyRuntime,
    render: Render,
    state: State,
    game_session: ?*GameSession,

    pub fn init(runtime: AnyRuntime) !Game {
        var instance = Game{
            .runtime = runtime,
            .render = Render{ .runtime = runtime },
            .state = .welcome,
            .game_session = null,
        };
        try instance.welcome();
        return instance;
    }

    pub fn deinit(self: Game) void {
        if (self.game_session) |session| session.destroy();
    }

    pub fn tick(self: *Game) !void {
        switch (self.state) {
            .welcome => if (try self.runtime.readPushedButtons()) |btn| {
                switch (btn.code) {
                    Buttons.A => try self.newGame(),
                    else => {},
                }
            },
            .game_over => if (try self.runtime.readPushedButtons()) |btn| {
                switch (btn.code) {
                    Buttons.A => try self.welcome(),
                    else => {},
                }
            },
            .game => if (self.game_session) |session| try session.tick(),
        }
    }

    inline fn welcome(self: *Game) !void {
        self.state = .welcome;
        try self.render.drawWelcomeScreen();
    }

    pub fn gameOver(self: *Game) !void {
        self.state = .game_over;
        try self.render.drawGameOverScreen();
    }

    inline fn newGame(self: *Game) !void {
        self.state = .game;
        if (self.game_session) |session| session.destroy();
        self.game_session = try GameSession.create(self);
    }
};

test {
    std.testing.refAllDecls(@This());
}
