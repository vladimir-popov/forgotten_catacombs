const std = @import("std");
const ecs = @import("ecs");
const algs_and_types = @import("algs_and_types");
const cmp = @import("components.zig");
const ent = @import("entities.zig");

const panic = std.debug.panic;

const Self = @This();

// ========= Export: ======================
pub usingnamespace cmp;

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
        drawDungeon: *const fn (context: *anyopaque, dungeon: *const cmp.Dungeon) anyerror!void,
        drawSprite: *const fn (context: *anyopaque, sprite: *const cmp.Sprite, row: u8, col: u8) anyerror!void,
    };

    context: *anyopaque,
    alloc: std.mem.Allocator,
    rand: std.Random,
    vtable: VTable,

    pub fn readButton(self: AnyRuntime) !?Button.Type {
        return try self.vtable.readButton(self.context);
    }

    pub fn drawDungeon(self: AnyRuntime, dungeon: *const cmp.Dungeon) !void {
        try self.vtable.drawDungeon(self.context, dungeon);
    }

    pub fn drawSprite(self: AnyRuntime, sprite: *const cmp.Sprite, row: u8, col: u8) !void {
        try self.vtable.drawSprite(self.context, sprite, row, col);
    }
};

pub const ForgottenCatacomb = struct {
    pub const Universe = ecs.Universe(cmp.Components, Events, AnyRuntime);

    pub fn init(runtime: AnyRuntime) !Universe {
        var universe: Universe = Universe.init(runtime.alloc, runtime);

        // Create entities:
        const entity = universe.newEntity();
        try ent.Level(entity, runtime.alloc, runtime.rand);
        ent.Player(entity, 2, 2);

        // Initialize systems:
        universe.registerSystem(handleInput);
        universe.registerSystem(render);

        universe.fireEvent(Events.gameHasBeenInitialized);
        return universe;
    }

    fn handleInput(universe: *Universe) anyerror!void {
        const btn = try universe.runtime.readButton() orelse return;
        if (!Button.isMove(btn)) return;

        universe.fireEvent(Events.buttonWasPressed);

        const level = universe.getComponents(cmp.Level)[0];
        var entities = universe.entitiesIterator();
        while (entities.next()) |entity| {
            if (universe.getComponent(entity, cmp.Position)) |position| {
                var new_position: cmp.Position = position.*;
                if (btn & Button.Up > 0)
                    new_position.row -= 1;
                if (btn & Button.Down > 0)
                    new_position.row += 1;
                if (btn & Button.Left > 0)
                    new_position.col -= 1;
                if (btn & Button.Right > 0)
                    new_position.col += 1;

                if (!level.dungeon.walls.isSet(new_position.row, new_position.col))
                    position.* = new_position;
            }
        }
    }

    fn render(universe: *Universe) anyerror!void {
        if (!(universe.isEventFired(Events.gameHasBeenInitialized) or universe.isEventFired(Events.buttonWasPressed)))
            return;

        const level = universe.getComponents(cmp.Level)[0];
        try universe.runtime.drawDungeon(&level.dungeon);

        var itr = universe.entitiesIterator();
        while (itr.next()) |entity| {
            if (universe.getComponent(entity, cmp.Position)) |position| {
                if (universe.getComponent(entity, cmp.Sprite)) |sprite| {
                    try universe.runtime.drawSprite(sprite, position.row, position.col);
                }
            }
        }
    }
};

test {
    std.testing.refAllDecls(Self);
}
