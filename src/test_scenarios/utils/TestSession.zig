const std = @import("std");
const g = @import("game");
const c = g.components;
const p = g.primitives;
const TestRuntime = @import("TestRuntime.zig");
const Inventory = @import("Inventory.zig");
const Player = @import("Player.zig");
const TestLocation = @import("TestLocation.zig");

pub const log = std.log.scoped(.test_session);

const Self = @This();

arena: std.heap.ArenaAllocator,
runtime: TestRuntime,
render: g.Render,
session: g.GameSession,
player: Player,
tmp_dir: std.testing.TmpDir,

/// Creates a new game session with TestRuntime and the first level.
pub fn initOnFirstLevel(self: *Self, gpa: std.mem.Allocator, io: std.Io) !void {
    self.tmp_dir = std.testing.tmpDir(.{});
    self.arena = std.heap.ArenaAllocator.init(gpa);
    const arena_alloc = self.arena.allocator();
    log.info("Test directory is {s}", .{try self.tmp_dir.dir.realPathFileAlloc(io, ".", arena_alloc)});
    self.runtime = try TestRuntime.init(arena_alloc, io, self.tmp_dir.dir);
    try self.render.init(arena_alloc, self.runtime.runtime(), g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.session.initNew(
        arena_alloc,
        std.testing.random_seed,
        self.runtime.runtime(),
        self.render,
        .zeros,
        .zeros,
        .init(30),
    );
    self.player = .{ .test_session = self, .id = self.session.player };
    // because for optimization purpose we draw the horizontal line right in init method of the PlayMode
    self.runtime.display.merge(self.runtime.last_frame);
}

/// ```
///••••••••••••••••••••••••••••••••••••••30
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///•••••••••••••••••••@••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///••••••••••••••••••••••••••••••••••••••••
///════════════════════════════════════════
///                    ⇧Explore ��  Wait  ⇧
/// ```
pub fn initWithTestArea(self: *Self, gpa: std.mem.Allocator, io: std.Io) !void {
    // TODO: Refactor to not create a first level here
    try self.initOnFirstLevel(gpa, io);
    for (self.session.level.entities_on_level.items) |entity| {
        if (!entity.eql(self.session.player)) {
            try self.session.registry.removeEntity(entity);
        }
    }
    self.session.level.deinit();
    self.session.level = g.Level.preInit(self.session.arena.allocator(), &self.session.registry);
    const level = &self.session.level;
    const dungeon = try TestLocation.generateDungeon(&self.session.level.arena);
    try level.setupDungeon(0, dungeon, self.session.player);
    try level.completeInitialization(null);
    const center = p.Point.init((g.DISPLAY_ROWS - 2) / 2, g.DISPLAY_COLS / 2);
    self.session.registry.getUnsafe(self.session.player, c.Position).place = center;
    self.session.viewport.region.top_left = .init(1, 1);
}

pub fn load(self: *Self, gpa: std.mem.Allocator, io: std.Io, working_dir: std.testing.TmpDir) !void {
    self.tmp_dir = working_dir;
    self.arena = std.heap.ArenaAllocator.init(gpa);
    const arena_alloc = self.arena.allocator();
    self.runtime = try TestRuntime.init(arena_alloc, io, self.tmp_dir.dir);
    try self.render.init(arena_alloc, self.runtime.runtime(), g.DISPLAY_ROWS, g.DISPLAY_COLS);
    try self.session.preInit(
        arena_alloc,
        self.runtime.runtime(),
        self.render,
    );
    try self.session.switchModeToLoadingSession();
}

pub fn deinit(self: *Self) void {
    self.tmp_dir.cleanup();
    self.arena.deinit();
}

/// Creates a new empty last_frame buffer, runs the method `session.tick()`,
/// and merges the last_frame into the display buffer.
pub fn tick(self: *Self) !void {
    self.runtime.last_frame = .empty;
    try self.session.tick();
    self.runtime.display.merge(self.runtime.last_frame);
}

pub fn completeRound(self: *Self) !void {
    std.debug.assert(self.session.mode == .play);
    while (!self.session.mode.play.is_player_turn) {
        try self.tick();
    }
}

pub fn printDisplay(self: Self) void {
    std.debug.print("{f}", .{std.fmt.alt(self.runtime.display, .ttyFormat)});
}

/// Emulates pressing a button and ticks one time.
/// Note, this method do not ticks until the next player's turn.
/// Invoke explicitly `completeRound` between pressing buttons more than once.
pub fn pressButton(self: *Self, button: g.Button.GameButton) !void {
    log.debug("Emulate pressing button {any}", .{button});
    try self.runtime.pushed_buttons.append(self.arena.allocator(), .{ .game_button = button, .state = .released });
    try self.tick();
}

pub fn openInventory(self: *Self) !Inventory {
    try self.session.manageInventory();
    try self.tick();
    return .{ .test_session = self };
}

pub fn exploreMode(self: *Self) !void {
    try self.session.lookAround();
    try self.tick();
}
