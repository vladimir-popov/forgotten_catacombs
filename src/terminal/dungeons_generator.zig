const std = @import("std");
const ecs = @import("ecs");
const gm = @import("game");
const tty = @import("tty.zig");

const Runtime = @import("Runtime.zig");
const Walls = gm.Level.Walls;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var runtime = try Runtime.init(alloc, std.crypto.random, &arena);
    defer runtime.deinit();
    var game = try DungeonsGenerator.init(alloc, std.crypto.random, runtime.any());
    defer game.deinit();

    try runtime.run(&game);
}

const Components = union(enum) {
    dungeon: Walls,

    fn deinitAll(components: Components) void {
        switch (components) {
            .dungeon => components.dungeon.deinit(),
        }
    }
};

const DungeonsGenerator = struct {
    const Self = @This();
    pub const Game = ecs.Game(Components, gm.Events, gm.AnyRuntime);

    pub fn init(
        alloc: std.mem.Allocator,
        rand: std.Random,
        runtime: gm.AnyRuntime,
    ) !Game {
        var game: Game = Game.init(alloc, runtime, Components.deinitAll);

        // Generate dungeon:
        const dungeon = try gm.generateMap(alloc, rand, 40, 150, 10, 10);

        const entity = game.newEntity();
        entity.addComponent(Walls, dungeon);

        // Initialize systems:
        game.registerSystem(handleInput);
        game.registerSystem(render);

        game.fireEvent(gm.Events.gameHasBeenInitialized);
        return game;
    }

    fn handleInput(game: *Game) anyerror!void {
        const btn = try game.runtime.readButton() orelse return;

        game.fireEvent(gm.Events.buttonWasPressed);

        if (btn & gm.Button.A > 0) {
            var entities = game.entitiesIterator();
            while (entities.next()) |entity| {
                if (game.getComponent(entity, Walls)) |_| {
                    game.removeComponentFromEntity(entity, Walls);
                    const dungeon = try gm.generateMap(game.runtime.alloc, game.runtime.rand, 40, 150, 10, 10);
                    game.addComponent(entity, Walls, dungeon);
                }
            }
        }
    }

    fn render(game: *Game) anyerror!void {
        if (!(game.isEventFired(gm.Events.gameHasBeenInitialized) or game.isEventFired(gm.Events.buttonWasPressed)))
            return;
        const walls = game.getComponents(Walls)[0];
        try game.runtime.drawWalls(&walls);
    }
};

test {
    std.testing.refAllDecls(@This());
}
