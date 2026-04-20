//! This is the root object for a single game session. The GameSession has different modes such as:
//! the `PlayMode`, `ExploreMode`, `ExploreLevelMode` and so on. These modes are extracted
//! to separate files to make their maintenance easier.
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

// zig copies a tagged union on stack in switch statement.
// this is why all values must be very compacted
pub const State = union(enum) {
    inited,
    welcome: *WelcomeScreen,
    create_character: *g.CharacterBuilder,
    /// The current game session
    game_session: *g.GameSession,
    game_over,
};

/// Used to allocate memory for the current state
state_arena: g.GameStateArena,
/// Playdate or terminal
runtime: g.Runtime,
/// Buffered render to draw the game
render: g.Render,
/// The seed is used to generate a new game session.
/// This seed can be passed by the user.
seed: u64,
/// The current state of the game
state: State,

pub fn init(gpa: std.mem.Allocator, runtime: g.Runtime, seed: u64) !Self {
    return .{
        .state_arena = .init(gpa),
        .runtime = runtime,
        .render = try .init(gpa, runtime),
        .seed = seed,
        .state = .inited,
    };
}

pub fn deinit(self: *Self) void {
    self.render.deinit();
    self.state_arena.deinit();
}

pub fn tick(self: *Self) !void {
    switch (self.state) {
        .inited => try self.welcome(),
        .welcome => if (try self.runtime.readPushedButtons()) |btn| {
            _ = try self.state.welcome.menu.handleButton(btn);
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
                const stats, const skills, const health = tuple;
                try self.startGameSession(stats, skills, health);
            } else {
                try self.state.create_character.draw(self.render);
            }
        },
        .game_session => |session| {
            session.tick() catch |err| switch (err) {
                error.GameOver => {
                    try self.deleteSessionFileIfExists();
                    _ = self.state_arena.reset(.retain_capacity);
                    self.state = .game_over;
                    try self.drawGameOverScreen();
                },
                error.GoToMainMenu => {
                    try self.welcome();
                },
                else => return err,
            };
        },
    }
}

/// Changes the current state to the `welcome`,
/// removes all items from the global menu, and draws the Welcome screen.
noinline fn welcome(self: *Self) !void {
    log.debug("Welcome screen. The game state is {t}", .{self.state});
    _ = self.state_arena.reset(.retain_capacity);
    self.state = .{ .welcome = try self.state_arena.allocator().create(WelcomeScreen) };
    self.state.welcome.menu = .init(self, .center);
    self.state.welcome.menu.selected_line = 0;

    self.runtime.removeAllMenuItems();

    const alloc = self.state_arena.allocator();
    // The choice will be handled manually in the `tick` method
    if (try self.isSessionFileExists())
        try self.state.welcome.menu.addOption(alloc, " Continue ", {}, continueGame, null);
    try self.state.welcome.menu.addOption(alloc, " New game ", {}, newGame, null);
    try self.state.welcome.menu.addOption(alloc, "  Manual  ", {}, showManual, null);
    try self.state.welcome.menu.addOption(alloc, "  About   ", {}, showAbout, null);

    try self.render.clearDisplay();
    try self.drawWelcomeScreen();
}

fn newGame(ptr: *anyopaque, _: usize, _: void) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    std.debug.assert(self.state == .welcome);
    try self.render.clearDisplay();
    _ = self.state_arena.reset(.retain_capacity);
    self.state = .{ .create_character = try self.state_arena.allocator().create(g.CharacterBuilder) };
    try self.state.create_character.init(&self.state_arena);
    try self.state.create_character.draw(self.render);
    return false;
}

pub fn startWithPreset(self: *Self, archetype: g.meta.PlayerArchetype, skills: c.Skills) !void {
    const stats = g.meta.statsFromArchetype(archetype);
    try self.startGameSession(stats, skills, g.meta.initialHealth(stats.constitution));
}

fn startGameSession(self: *Self, stats: c.Stats, skills: c.Skills, health: c.Health) !void {
    try self.render.clearDisplay();
    try self.deleteSessionFileIfExists();
    log.debug("Init menu", .{});
    self.initSideMenu();
    log.debug("Menu inited", .{});
    _ = self.state_arena.reset(.retain_capacity);
    self.state = .{ .game_session = try self.state_arena.allocator().create(g.GameSession) };
    try self.state.game_session.initNew(
        &self.state_arena,
        self.seed,
        self.runtime,
        self.render,
        stats,
        skills,
        health,
    );
    log.debug("New session inited", .{});
}

fn continueGame(ptr: *anyopaque, _: usize, _: void) !bool {
    const self: *Self = @ptrCast(@alignCast(ptr));
    std.debug.assert(self.state == .welcome);
    self.initSideMenu();
    _ = self.state_arena.reset(.retain_capacity);
    self.state = .{ .game_session = try self.state_arena.allocator().create(g.GameSession) };
    try self.state.game_session.preInit(
        &self.state_arena,
        self.runtime,
        self.render,
    );
    try self.state.game_session.switchModeToLoadingSession(&self.state_arena);
    return false;
}

fn showManual(_: *anyopaque, _: usize, _: void) !bool {
    return false;
}

fn showAbout(_: *anyopaque, _: usize, _: void) !bool {
    return false;
}

fn initSideMenu(self: *Self) void {
    _ = self.runtime.addMenuItem("Inventory", self, openInventory);
    _ = self.runtime.addMenuItem("Main menu", self, goToMainMenu);
}

fn goToMainMenu(null_ptr: ?*anyopaque) callconv(.c) void {
    if (null_ptr) |ptr| {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.debug.assert(self.state == .game_session);
        self.state.game_session.switchModeToSavingSession() catch |err|
            std.debug.panic("Error on switching to SaveSession: {any}", .{err});
    }
}

fn openInventory(null_ptr: ?*anyopaque) callconv(.c) void {
    if (null_ptr) |ptr| {
        const self: *Self = @ptrCast(@alignCast(ptr));
        std.debug.assert(self.state == .game_session);
        self.state.game_session.manageInventory() catch |err|
            std.debug.panic("Error on opening inventory: {any}", .{err});
    }
}

/// Checks that save file for a session exists.
fn isSessionFileExists(self: Self) !bool {
    return self.runtime.isFileExists(g.persistance.SESSION_FILE_NAME);
}

/// Remove the save file with a game session if it exists.
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
