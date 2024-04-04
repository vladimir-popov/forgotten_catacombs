const std = @import("std");
const ecs = @import("ecs");
const cmp = @import("components.zig");

const panic = std.debug.panic;

// ========= Export: ======================
pub usingnamespace cmp;

pub fn Runtime(comptime Environment: type) type {
    return struct {
        const Self = @This();

        const VTable = struct {
            drawSprite: *const fn (state: *Environment, sprite: *const cmp.Sprite, row: u8, col: u8) anyerror!void,
        };

        environment: *Environment,
        vtable: VTable,

        pub fn drawSprite(self: *Self, sprite: *const cmp.Sprite, row: u8, col: u8) !void {
            try self.vtable.drawSprite(self.environment, sprite, row, col);
        }
    };
}

pub fn ForgottenCatacomb(comptime Environment: type) type {
    return struct {
        const Self = @This();
        pub const Game = ecs.Game(cmp.AllComponents, Runtime(Environment));

        pub fn init(runtime: Runtime(Environment), alloc: std.mem.Allocator) Game {
            var game: Game = Game.init(runtime, alloc);
            var entity = game.newEntity();
            entity.addComponent(cmp.Position, .{ .row = 2, .col = 2 });
            entity.addComponent(cmp.Sprite, .{ .letter = "@" });
            game.registerSystem(render);
            return game;
        }

        fn render(game: *Game) anyerror!void {
            var itr = game.entitiesIterator();
            while (itr.next()) |entity| {
                if (game.getComponent(entity, cmp.Position)) |position_ptr| {
                    if (game.getComponent(entity, cmp.Sprite)) |sprite_ptr| {
                        try game.runtime.drawSprite(sprite_ptr, position_ptr.row, position_ptr.col);
                    }
                }
            }
        }
    };
}
