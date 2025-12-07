const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const p = g.primitives;
const w = g.windows;

const log = std.log.scoped(.game);

const Self = @This();

const VERTICAL_MIDDLE = g.DISPLAY_ROWS / 2;
const HORIZONTAL_MIDDLE = g.DISPLAY_COLS / 2;

const WelcomeScreen = struct {
    const MenuOption = enum { Continue, NewGame, Manual };
    const MENU_REGION = p.Region.init(VERTICAL_MIDDLE + 2, HORIZONTAL_MIDDLE - 6, 5, 12);

    menu: w.OptionsArea(void),
    selected_option: usize = 0,

    fn menuOption(self: WelcomeScreen) MenuOption {
        return if (self.menu.lines.items.len == 2)
            @enumFromInt(self.selected_option + 1)
        else
            @enumFromInt(self.selected_option);
    }
};

pub const State = union(enum) {
    welcome: WelcomeScreen,
    create_character: g.CharacterBuilder,
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
    try self.render.init(gpa, runtime, g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.welcome();
}

pub fn initNewPreset(
    self: *Self,
    gpa: std.mem.Allocator,
    runtime: g.Runtime,
    seed: u64,
    archetype: g.meta.PlayerArchetype,
    skills: g.components.Skills,
) !void {
    self.* = .{
        .gpa = gpa,
        .runtime = runtime,
        .render = undefined,
        .seed = seed,
        .state = undefined,
    };
    try self.render.init(gpa, runtime, g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.runtime.clearDisplay();
    try self.startGameSession(g.meta.statsFromArchetype(archetype), skills);
}

pub fn deinit(self: *Self) void {
    self.render.deinit();
    switch (self.state) {
        .welcome => self.state.welcome.menu.deinit(self.gpa),
        .create_character => self.state.create_character.deinit(),
        .game_session => self.state.game_session.deinit(),
        .game_over => {},
    }
}

pub fn tick(self: *Self) !void {
    switch (self.state) {
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            try self.state.welcome.menu.handleButton(btn);
            if (btn.game_button.isMove())
                try self.state.welcome.menu.draw(self.render, WelcomeScreen.MENU_REGION, 0);
        },
        .game_over => if (try self.runtime.readPushedButtons()) |btn| {
            switch (btn.game_button) {
                .a => if (btn.state == .released) try self.welcome(),
                else => {},
            }
        },
        .create_character => if (try self.runtime.readPushedButtons()) |btn| {
            if (try self.state.create_character.handleButton(btn, self.render)) |tuple| {
                self.state.create_character.deinit();
                try self.startGameSession(tuple[0], tuple[1]);
            } else {
                try self.state.create_character.draw(self.render);
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
    self.state = .{ .welcome = .{ .menu = w.OptionsArea(void).init(self, .center) } };
    self.state.welcome.menu.selected_line = 0;

    self.runtime.removeAllMenuItems();

    // The choice will be handled manually in the `tick` method
    if (try self.isSessionFileExists())
        try self.state.welcome.menu.addOption(self.gpa, " Continue ", {}, continueGame, null);
    try self.state.welcome.menu.addOption(self.gpa, " New game ", {}, newGame, null);
    try self.state.welcome.menu.addOption(self.gpa, "  About   ", {}, showAbout, null);

    try self.render.clearDisplay();
    try self.drawWelcomeScreen();
}

fn newGame(ptr: *anyopaque, _: usize, _: void) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    std.debug.assert(self.state == .welcome);
    self.state.welcome.menu.deinit(self.gpa);
    try self.render.clearDisplay();
    self.state = .{ .create_character = undefined };
    try self.state.create_character.init(self.gpa);
    try self.state.create_character.draw(self.render);
}

fn startGameSession(self: *Self, stats: c.Stats, skills: c.Skills) !void {
    try self.deleteSessionFileIfExists();
    self.initSideMenu();
    self.state = .{ .game_session = undefined };
    try self.state.game_session.initNew(
        self.gpa,
        self.seed,
        self.runtime,
        self.render,
        stats,
        skills,
    );
}

fn continueGame(ptr: *anyopaque, _: usize, _: void) !void {
    const self: *Self = @ptrCast(@alignCast(ptr));
    std.debug.assert(self.state == .welcome);
    self.state.welcome.menu.deinit(self.gpa);
    self.initSideMenu();
    self.state = .{ .game_session = undefined };
    try self.state.game_session.preInit(
        self.gpa,
        self.runtime,
        self.render,
    );
    try self.state.game_session.switchModeToLoadingSession();
}

fn showAbout(_: *anyopaque, _: usize, _: void) !void {}

fn initSideMenu(self: *Self) void {
    _ = self.runtime.addMenuItem("Inventory", self, openInventory);
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
}

fn goToMainMenu(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr.?));
    std.debug.assert(self.state == .game_session);
    self.state.game_session.switchModeToSavingSession();
}

fn openInventory(ptr: ?*anyopaque) callconv(.c) void {
    if (ptr == null) return;
    const self: *Self = @ptrCast(@alignCast(ptr.?));
    std.debug.assert(self.state == .game_session);
    self.state.game_session.manageInventory() catch |err| std.debug.panic("Error on open inventory: {any}", .{err});
}

/// Checks that save file for a session exists.
fn isSessionFileExists(self: Self) !bool {
    return self.runtime.isFileExists(g.persistance.SESSION_FILE_NAME);
}

/// Remove the save file with a game session if exists.
fn deleteSessionFileIfExists(self: Self) !void {
    try self.runtime.deleteFileIfExists(g.persistance.SESSION_FILE_NAME);
}

fn drawWelcomeScreen(self: Self) !void {
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Welcome ",
        .{ .row = VERTICAL_MIDDLE - 3, .col = 1 },
        .normal,
        .center,
    );
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "to ",
        .{ .row = VERTICAL_MIDDLE - 2, .col = 1 },
        .normal,
        .center,
    );
    try self.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        "Forgotten catacombs",
        .{ .row = VERTICAL_MIDDLE - 1, .col = 1 },
        .normal,
        .center,
    );
    try self.state.welcome.menu.draw(self.render, WelcomeScreen.MENU_REGION, 0);
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
