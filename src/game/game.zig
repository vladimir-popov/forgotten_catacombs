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
    vtable: *const VTable,

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

pub const GameSession = struct {
    const Self = @This();

    const System = *const fn (game: *Self) anyerror!void;

    pub const Timers = enum { input_system };

    runtime: AnyRuntime,
    screen: Screen,
    timers: []i64,
    player: Entity,
    dungeon: *Dungeon,
    entities: std.ArrayList(Entity),
    systems: std.ArrayList(System),
    positions: ecs.ComponentArray(components.Position),
    moves: ecs.ComponentArray(components.Move),
    sprites: ecs.ComponentArray(components.Sprite),

    pub fn create(runtime: AnyRuntime) !*Self {
        const dungeon = try Dungeon.createRandom(runtime.alloc, runtime.rand);
        const player_position = dungeon.findRandomPlaceForPlayer();
        const session = try runtime.alloc.create(Self);
        session.* = .{
            .runtime = runtime,
            .screen = Screen.init(DISPLAY_ROWS, DISPLAY_COLS, Dungeon.Region),
            .timers = try runtime.alloc.alloc(i64, std.meta.tags(GameSession.Timers).len),
            .player = 0,
            .dungeon = dungeon,
            .entities = std.ArrayList(Entity).init(runtime.alloc),
            .systems = std.ArrayList(System).init(runtime.alloc),
            .positions = ecs.ComponentArray(components.Position).init(runtime.alloc),
            .moves = ecs.ComponentArray(components.Move).init(runtime.alloc),
            .sprites = ecs.ComponentArray(components.Sprite).init(runtime.alloc),
        };
        try session.entities.append(session.player);
        session.screen.centeredAround(player_position);
        session.positions.addToEntity(session.player, .{ .point = player_position });
        session.moves.addToEntity(session.player, .{});
        session.sprites.addToEntity(session.player, .{ .letter = "@" });

        // Initialize systems:
        // session.systems.append(systems.Input.handleInput);
        // session.systems.append(systems.Movement.handleMove);
        try session.systems.append(systems.Render.render);

        return session;
    }

    pub fn destroy(self: *GameSession) void {
        self.runtime.alloc.free(self.timers);
        self.dungeon.destroy();
        self.entities.deinit();
        self.systems.deinit();
        self.positions.deinit();
        self.moves.deinit();
        self.sprites.deinit();
        self.runtime.alloc.destroy(self);
    }

    pub inline fn timer(self: GameSession, t: Timers) *i64 {
        return &self.timers[@intFromEnum(t)];
    }

    pub fn tick(self: *Self) anyerror!void {
        for (self.systems.items) |system| {
            try system(self);
        }
    }
};
