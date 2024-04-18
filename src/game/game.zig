const std = @import("std");
const ecs = @import("ecs");
const cmp = @import("components.zig");
const ent = @import("entities.zig");

const panic = std.debug.panic;

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
    const Self = @This();

    pub const count = @typeInfo(Self).Enum.fields.len;

    gameHasBeenInitialized,
    buttonWasPressed,

    pub fn index(self: Self) u8 {
        return @intFromEnum(self);
    }
};

pub const AnyRuntime = struct {
    const Self = @This();

    const VTable = struct {
        readButton: *const fn (context: *anyopaque) anyerror!?Button.Type,
        drawLevel: *const fn (context: *anyopaque, level: *const cmp.Level) anyerror!void,
        drawSprite: *const fn (context: *anyopaque, sprite: *const cmp.Sprite, row: u8, col: u8) anyerror!void,
    };

    context: *anyopaque,
    vtable: VTable,

    pub fn readButton(self: Self) !?Button.Type {
        return try self.vtable.readButton(self.context);
    }

    pub fn drawLevel(self: Self, level: *const cmp.Level) !void {
        try self.vtable.drawLevel(self.context, level);
    }

    pub fn drawSprite(self: *Self, sprite: *const cmp.Sprite, row: u8, col: u8) !void {
        try self.vtable.drawSprite(self.context, sprite, row, col);
    }
};

pub const ForgottenCatacomb = struct {
    const Self = @This();
    pub const Game = ecs.Game(cmp.AllComponents, Events, AnyRuntime);

    pub fn init(alloc: std.mem.Allocator, runtime: AnyRuntime) !Game {
        var game: Game = Game.init(alloc, runtime);

        // Create entities:
        const entity = game.newEntity();
        try ent.Level(entity, alloc, 20, 50);
        ent.Player(entity, 2, 2);

        // Initialize systems:
        game.registerSystem(handleInput);
        game.registerSystem(render);

        game.fireEvent(Events.gameHasBeenInitialized);
        return game;
    }

    fn handleInput(game: *Game) anyerror!void {
        const btn = try game.runtime.readButton() orelse return;
        if (!Button.isMove(btn)) return;

        game.fireEvent(Events.buttonWasPressed);

        const level = game.getComponents(cmp.Level)[0];
        var entities = game.entitiesIterator();
        while (entities.next()) |entity| {
            if (game.getComponent(entity, cmp.Position)) |position| {
                var new_position: cmp.Position = position.*;
                if (btn & Button.Up > 0)
                    new_position.row -= 1;
                if (btn & Button.Down > 0)
                    new_position.row += 1;
                if (btn & Button.Left > 0)
                    new_position.col -= 1;
                if (btn & Button.Right > 0)
                    new_position.col += 1;

                if (!level.hasWall(new_position))
                    position.* = new_position;
            }
        }
    }

    fn render(game: *Game) anyerror!void {
        if (!(game.isEventFired(Events.gameHasBeenInitialized) or game.isEventFired(Events.buttonWasPressed)))
            return;

        const level = game.getComponents(cmp.Level)[0];
        try game.runtime.drawLevel(&level);

        var itr = game.entitiesIterator();
        while (itr.next()) |entity| {
            if (game.getComponent(entity, cmp.Position)) |position| {
                if (game.getComponent(entity, cmp.Sprite)) |sprite| {
                    try game.runtime.drawSprite(sprite, position.row, position.col);
                }
            }
        }
    }
};
