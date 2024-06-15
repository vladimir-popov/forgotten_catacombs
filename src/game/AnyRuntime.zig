const std = @import("std");
const algs_and_types = @import("algs_and_types");
const p = algs_and_types.primitives;
const game = @import("game.zig");

const Self = @This();

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

const VTable = struct {
    readButton: *const fn (context: *anyopaque) anyerror!Button.Type,
    drawDungeon: *const fn (
        context: *anyopaque,
        screen: *const game.Screen,
        dungeon: *const game.Dungeon,
    ) anyerror!void,
    drawSprite: *const fn (
        context: *anyopaque,
        screen: *const game.Screen,
        sprite: *const game.Sprite,
        position: *const game.Position,
    ) anyerror!void,
    currentMillis: *const fn (context: *anyopaque) i64,
};

context: *anyopaque,
alloc: std.mem.Allocator,
rand: std.Random,
vtable: *const VTable,

pub fn currentMillis(self: Self) i64 {
    return self.vtable.currentMillis(self.context);
}

pub fn readButton(self: Self) !Button.Type {
    return try self.vtable.readButton(self.context);
}

pub fn drawDungeon(
    self: Self,
    screen: *const game.Screen,
    dungeon: *const game.Dungeon,
) !void {
    try self.vtable.drawDungeon(self.context, screen, dungeon);
}

pub fn drawSprite(
    self: Self,
    screen: *const game.Screen,
    sprite: *const game.Sprite,
    position: *const game.Position,
) !void {
    try self.vtable.drawSprite(self.context, screen, sprite, position);
}
