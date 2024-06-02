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

const panic = std.debug.panic;

const Self = @This();

pub const Entity = ecs.Entity;

pub const Button = struct {
    pub const Type = u8;

    pub const Left: Type = (1 << 0);
    pub const Right: Type = (1 << 1);
    pub const Up: Type = (1 << 2);
    pub const Down: Type = (1 << 3);
    pub const B: Type = (1 << 4);
    pub const A: Type = (1 << 5);

    pub inline fn isMove(btn: Type) bool {
        return (Up | Down | Left | Right) & btn > 0;
    }
};

pub const Components = union {
    screen: components.Screen,
    level: components.Level,
    dungeon: components.Dungeon,
    health: components.Health,
    position: components.Position,
    move: components.Move,
    sprite: components.Sprite,
};

/// Possible events which can be passed between systems.
pub const Events = enum {
    gameHasBeenInitialized,
    buttonWasPressed,

    pub fn index(self: Events) u8 {
        return @intFromEnum(self);
    }
};

pub const AnyRuntime = struct {
    const VTable = struct {
        readButton: *const fn (context: *anyopaque) anyerror!?Button.Type,
        drawDungeon: *const fn (
            context: *anyopaque,
            screen: *const components.Screen,
            dungeon: *const components.Dungeon,
        ) anyerror!void,
        drawSprite: *const fn (
            context: *anyopaque,
            screen: *const components.Screen,
            sprite: *const components.Sprite,
            position: *const components.Position,
        ) anyerror!void,
    };

    context: *anyopaque,
    alloc: std.mem.Allocator,
    rand: std.Random,
    vtable: VTable,

    pub fn readButton(self: AnyRuntime) !?Button.Type {
        return try self.vtable.readButton(self.context);
    }

    pub fn drawDungeon(
        self: AnyRuntime,
        screen: *const components.Screen,
        dungeon: *const components.Dungeon,
    ) !void {
        try self.vtable.drawDungeon(self.context, screen, dungeon);
    }

    pub fn drawSprite(
        self: AnyRuntime,
        screen: *const components.Screen,
        sprite: *const components.Sprite,
        position: *const components.Position,
    ) !void {
        try self.vtable.drawSprite(self.context, screen, sprite, position);
    }
};

pub const Universe = ecs.Universe(Components, Events, AnyRuntime);

pub fn init(runtime: AnyRuntime) !Universe {
    var universe: Universe = Universe.init(runtime.alloc, runtime);

    const dungeon = try components.Dungeon.bspGenerate(runtime.alloc, runtime.rand);
    const player_position = dungeon.findRandomPlaceForPlayer();
    const player = entities.Player(universe, player_position);
    // init level
    _ = universe.newEntity()
        .withComponent(components.Level, .{ .player = player })
        .withComponent(components.Dungeon, dungeon)
        .withComponent(
        components.Screen,
        components.Screen.centeredAround(player_position, components.Dungeon.Region),
    );

    // Initialize systems:
    universe.registerSystem(systems.Input.handleInput);
    universe.registerSystem(systems.Movement.handleMove);
    universe.registerSystem(systems.Render.render);

    universe.fireEvent(Events.gameHasBeenInitialized);
    return universe;
}

test {
    std.testing.refAllDecls(Self);
}
