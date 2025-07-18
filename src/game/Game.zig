const std = @import("std");
const g = @import("game_pkg.zig");
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.game);

const Self = @This();

const vertical_middle = g.DISPLAY_ROWS / 2;
const horizontal_middle = g.DISPLAY_COLS / 2;

const WelcomeScreen = struct {
    const MenuOption = enum { Continue, NewGame, Manual };

    menu: w.TextArea,
    selected_option: usize = 0,

    fn menuOption(self: WelcomeScreen) MenuOption {
        return if (self.menu.lines.items.len == 2)
            @enumFromInt(self.selected_option + 1)
        else
            @enumFromInt(self.selected_option);
    }

    fn selectPreviousLine(self: *@This()) void {
        self.menu.unhighlightLine(self.selected_option);
        if (self.selected_option > 0)
            self.selected_option -= 1
        else
            self.selected_option = self.menu.lines.items.len - 1;
        self.menu.highlightLine(self.selected_option);
    }

    fn selectNextLine(self: *@This()) void {
        self.menu.unhighlightLine(self.selected_option);
        if (self.selected_option < self.menu.lines.items.len - 1)
            self.selected_option += 1
        else
            self.selected_option = 0;
        self.menu.highlightLine(self.selected_option);
    }
};

pub const State = union(enum) {
    welcome: WelcomeScreen,
    /// The current game session
    game_session: g.GameSession,
    game_over,
};

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

pub fn init(self: *Self, gpa: std.mem.Allocator, runtime: g.Runtime, seed: u64) !void {
    self.* = .{
        .gpa = gpa,
        .runtime = runtime,
        .render = undefined,
        .seed = seed,
        .state = undefined,
    };
    try self.render.init(gpa, runtime, g.DISPLAY_ROWS - 2, g.DISPLAY_COLS);
    try self.welcome();
}

pub fn deinit(self: *Self) void {
    self.render.deinit();
    switch (self.state) {
        .welcome => self.state.welcome.menu.deinit(self.gpa),
        .game_session => self.state.game_session.deinit(),
        .game_over => {},
    }
}

pub fn tick(self: *Self) !void {
    switch (self.state) {
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) {
                    switch (self.state.welcome.menuOption()) {
                        .NewGame => {
                            self.state.welcome.menu.deinit(self.gpa);
                            try self.newGame();
                        },
                        .Continue => {
                            self.state.welcome.menu.deinit(self.gpa);
                            try self.continueGame();
                        },
                        else => {},
                    }
                },
                .up => {
                    self.state.welcome.selectPreviousLine();
                    try self.state.welcome.menu.draw(self.render);
                },
                .down => {
                    self.state.welcome.selectNextLine();
                    try self.state.welcome.menu.draw(self.render);
                },
                else => {},
            }
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) try self.welcome(),
                else => {},
            }
        },
        .game_session => |*session| {
            session.tick() catch |err| switch (err) {
                error.GameOver => {
                    self.state.game_session.deinit();
                    try self.deleteSessionFileIfExists();
                    self.state = .game_over;
                    try self.drawGameOverScreen();
                },
                error.GoToMainMenu => {
                    self.state.game_session.deinit();
                    try self.welcome();
                },
                else => return err,
            };
        },
    }
}

/// Changes the current state to the `welcome`,
/// removes all items from the global menu, and draws the Welcome screen.
pub fn welcome(self: *Self) !void {
    log.debug("Welcome screen. The game state is {s}", .{@tagName(self.state)});
    self.state = .{ .welcome = .{ .menu = w.TextArea.init(.{
        .region = p.Region.init(vertical_middle + 1, horizontal_middle - 6, 5, 12),
    }) } };

    self.runtime.removeAllMenuItems();

    if (try self.isSessionFileExists())
        try self.state.welcome.menu.addLine(self.gpa, " Continue ", true);
    try self.state.welcome.menu.addLine(self.gpa, " New game ", !try self.isSessionFileExists());
    try self.state.welcome.menu.addLine(self.gpa, "  About   ", false);

    try self.render.clearDisplay();
    try self.drawWelcomeScreen();
}

fn newGame(self: *Self) !void {
    std.debug.assert(self.state != .game_session);
    try self.deleteSessionFileIfExists();
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    self.state = .{ .game_session = undefined };
    try self.state.game_session.initNew(
        self.gpa,
        self.seed,
        self.runtime,
        self.render,
    );
}

fn continueGame(self: *Self) !void {
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
    self.state = .{ .game_session = undefined };
    try self.state.game_session.preInit(
        self.gpa,
        self.runtime,
        self.render,
    );
    try self.state.game_session.load();
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.C) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr.?));
    std.debug.assert(self.state == .game_session);
    self.state.game_session.save();
}

/// Checks that save file for a session exists.
fn isSessionFileExists(self: Self) !bool {
    return self.runtime.isFileExists(g.persistance.PATH_TO_SESSION_FILE);
}

/// Remove the save file with a game session if exists.
fn deleteSessionFileIfExists(self: Self) !void {
    try self.runtime.deleteFileIfExists(g.persistance.PATH_TO_SESSION_FILE);
}

fn drawWelcomeScreen(self: Self) !void {
    try self.runtime.clearDisplay();
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Welcome ",
        .{ .row = vertical_middle - 3, .col = 1 },
        .normal,
        .center,
    );
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "to ",
        .{ .row = vertical_middle - 2, .col = 1 },
        .normal,
        .center,
    );
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Forgotten catacombs",
        .{ .row = vertical_middle - 1, .col = 1 },
        .normal,
        .center,
    );
    try self.state.welcome.menu.draw(self.render);
}

fn drawGameOverScreen(self: Self) !void {
    try self.render.clearDisplay();
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "You are dead",
        .{ .row = g.DISPLAY_ROWS / 2, .col = 1 },
        .normal,
        .center,
    );
}
