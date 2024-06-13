const std = @import("std");
const ecs = @import("ecs");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;

pub const entities = @import("entities.zig");
pub const components = @import("components.zig");
pub const systems = @import("systems.zig");

// Playdate resolution: h:240 × w:400 pixels
// we expect at least 4x4 sprite to render the whole level map
// and 16x8 to render the game in play mode

/// The maximum rows count in the dungeon
pub const TOTAL_ROWS: u8 = 40;
/// The maximum columns count in the dungeon
pub const TOTAL_COLS: u8 = 100;

/// The rows count to display
const DISPLAY_ROWS: u8 = 15;
/// The rows count to display
const DISPLAY_COLS: u8 = 40;

const ROWS_PAD = 3;
const COLS_PAD = 7;

const panic = std.debug.panic;

const Self = @This();

pub const Screen = @import("Screen.zig");

pub const Entity = ecs.Entity;

pub const Dungeon = @import("BspDungeon.zig").BspDungeon(TOTAL_ROWS, TOTAL_COLS);

pub const Button = struct {
    pub const Type = c_int;

    pub const None: Type = 0;
    pub const Left: Type = (1 << 0);
    pub const Right: Type = (1 << 1);
    pub const Up: Type = (1 << 2);
    pub const Down: Type = (1 << 3);
    pub const B: Type = (1 << 4);
    pub const A: Type = (1 << 5);

    pub inline fn isMove(btn: Type) bool {
        return (Up | Down | Left | Right) & btn > 0;
    }

    pub inline fn toDirection(btn: Button.Type) ?p.Direction {
        return if (btn & Button.Up > 0)
            p.Direction.up
        else if (btn & Button.Down > 0)
            p.Direction.down
        else if (btn & Button.Left > 0)
            p.Direction.left
        else if (btn & Button.Right > 0)
            p.Direction.right
        else
            null;
    }
};

pub const Components = union {
    health: components.Health,
    position: components.Position,
    move: components.Move,
    sprite: components.Sprite,
};

pub const AnyRuntime = struct {
    const VTable = struct {
        readButton: *const fn (context: *anyopaque) anyerror!Button.Type,
        drawDungeon: *const fn (
            context: *anyopaque,
            screen: *const Screen,
            dungeon: *const Dungeon,
        ) anyerror!void,
        drawSprite: *const fn (
            context: *anyopaque,
            screen: *const Screen,
            sprite: *const components.Sprite,
            position: *const components.Position,
        ) anyerror!void,
        currentMillis: *const fn (context: *anyopaque) i64,
    };

    context: *anyopaque,
    alloc: std.mem.Allocator,
    rand: std.Random,
    vtable: VTable,

    pub fn currentMillis(self: AnyRuntime) i64 {
        return self.vtable.currentMillis(self.context);
    }

    pub fn readButton(self: AnyRuntime) !Button.Type {
        return try self.vtable.readButton(self.context);
    }

    pub fn drawDungeon(
        self: AnyRuntime,
        screen: *const Screen,
        dungeon: *const Dungeon,
    ) !void {
        try self.vtable.drawDungeon(self.context, screen, dungeon);
    }

    pub fn drawSprite(
        self: AnyRuntime,
        screen: *const Screen,
        sprite: *const components.Sprite,
        position: *const components.Position,
    ) !void {
        try self.vtable.drawSprite(self.context, screen, sprite, position);
    }
};

pub const Universe = ecs.Universe(GameSession, Components, AnyRuntime);

pub const GameSession = struct {
    pub const Timers = enum { input_system };

    alloc: std.mem.Allocator,
    screen: Screen,
    timers: []i64,
    player: Entity,
    dungeon: *Dungeon,

    pub fn init(alloc: std.mem.Allocator, rand: std.Random, universe: *Universe) !void {
        const dungeon = try Dungeon.createRandom(alloc, rand);
        const player_position = dungeon.findRandomPlaceForPlayer();
        universe.root.* = .{
            .alloc = alloc,
            .screen = Screen.init(DISPLAY_ROWS, DISPLAY_COLS, Dungeon.Region),
            .timers = try alloc.alloc(i64, std.meta.tags(GameSession.Timers).len),
            .dungeon = dungeon,
            .player = entities.Player(universe, player_position),
        };
        universe.root.screen.centeredAround(player_position);
    }

    pub fn deinit(self: *GameSession) void {
        self.alloc.free(self.timers);
        self.dungeon.destroy();
    }

    pub inline fn timer(self: GameSession, t: Timers) *i64 {
        return &self.timers[@intFromEnum(t)];
    }
};

pub fn init(runtime: AnyRuntime) !Universe {
    var universe: Universe = try Universe.init(runtime.alloc, runtime);

    try GameSession.init(runtime.alloc, runtime.rand, &universe);

    // Initialize systems:
    universe.registerSystem(systems.Input.handleInput);
    universe.registerSystem(systems.Movement.handleMove);
    universe.registerSystem(systems.Render.render);

    return universe;
}

test {
    std.testing.refAllDecls(Self);
}
