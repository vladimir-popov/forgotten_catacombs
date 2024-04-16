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

    buttonWasPressed,

    pub fn index(self: Self) u8 {
        return @intFromEnum(self);
    }
};

pub fn Runtime(comptime Environment: type) type {
    return struct {
        const Self = @This();

        const VTable = struct {
            readButton: *const fn (state: *Environment) anyerror!?Button.Type,
            drawSprite: *const fn (state: *Environment, sprite: *const cmp.Sprite, row: u8, col: u8) anyerror!void,
        };

        rows: u8,
        cols: u8,
        environment: *Environment,
        vtable: VTable,
        events: std.StaticBitSet(Events.count) = std.StaticBitSet(Events.count).initEmpty(),

        pub fn fireEvent(self: *Self, event: Events) void {
            self.events.set(event.index());
        }

        pub fn isEventFired(self: Self, event: Events) bool {
            return self.events.isSet(event.index());
        }

        pub fn drawSprite(self: *Self, sprite: *const cmp.Sprite, row: u8, col: u8) !void {
            try self.vtable.drawSprite(self.environment, sprite, row, col);
        }

        pub fn readButton(self: Self) !?Button.Type {
            return try self.vtable.readButton(self.environment);
        }
    };
}

pub fn ForgottenCatacomb(comptime Environment: type) type {
    return struct {
        const Self = @This();
        pub const Game = ecs.Game(cmp.AllComponents, Runtime(Environment));

        pub fn init(runtime: Runtime(Environment), alloc: std.mem.Allocator) Game {
            var game: Game = Game.init(runtime, alloc);

            // Create entities:
            const entity = game.newEntity();
            ent.Player(entity);

            // Initialize systems:
            game.registerSystem(handleInput);
            game.registerSystem(render);

            game.registerSystem(cleanupEvents);
            return game;
        }

        fn cleanupEvents(game: *Game) anyerror!void {
            game.runtime.events.setRangeValue(.{ .start = 0, .end = Events.count }, false);
        }

        fn handleInput(game: *Game) anyerror!void {
            const btn = try game.runtime.readButton() orelse return;
            if (!Button.isMove(btn)) return;

            game.runtime.fireEvent(Events.buttonWasPressed);

            const step = 10;
            var itr = game.entitiesIterator();
            while (itr.next()) |entity| {
                if (game.getComponent(entity, cmp.Position)) |position| {
                    if (btn & Button.Up > 0 and position.row >= step)
                        position.row -= step;
                    if (btn & Button.Down > 0 and position.row < (game.runtime.rows - step))
                        position.row += step;
                    if (btn & Button.Left > 0 and position.col >= step)
                        position.col -= step;
                    if (btn & Button.Right > 0 and position.col < (game.runtime.cols - step))
                        position.col += step;
                }
            }
        }

        fn render(game: *Game) anyerror!void {
            if (!game.runtime.isEventFired(Events.buttonWasPressed))
                return;

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
}
