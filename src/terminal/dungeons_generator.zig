const std = @import("std");
const ecs = @import("ecs");
const gm = @import("game");
const tty = @import("tty.zig");

const Runtime = @import("Runtime.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const alloc = gpa.allocator();
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var runtime = try Runtime.init(alloc, std.crypto.random, &arena);
    defer runtime.deinit();
    var game = try DungeonsGenerator.init(runtime.any());
    defer game.deinit();

    try runtime.run(&game);
}

const Components = union(enum) {
    dungeon: gm.Dungeon,

    fn deinitAll(components: Components) void {
        switch (components) {
            .dungeon => components.dungeon.deinit(),
        }
    }
};

const DungeonsGenerator = struct {
    const Self = @This();
    pub const Game = ecs.Game(Components, gm.Events, gm.AnyRuntime);

    pub fn init(runtime: gm.AnyRuntime) !Game {
        var game: Game = Game.init(runtime.alloc, runtime, Components.deinitAll);

        // Generate dungeon:
        const dungeon = try gm.Dungeon.bspGenerate(
            game.runtime.alloc,
            game.runtime.rand,
            gm.Dungeon.ROWS,
            gm.Dungeon.COLS,
        );

        const entity = game.newEntity();
        entity.addComponent(gm.Dungeon, dungeon);

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
                if (game.getComponent(entity, gm.Dungeon)) |_| {
                    game.removeComponentFromEntity(entity, gm.Dungeon);
                    const dungeon = try gm.Dungeon.bspGenerate(
                        game.runtime.alloc,
                        game.runtime.rand,
                        gm.Dungeon.ROWS,
                        gm.Dungeon.COLS,
                    );
                    game.addComponent(entity, gm.Dungeon, dungeon);
                }
            }
        }
    }

    fn render(game: *Game) anyerror!void {
        if (!(game.isEventFired(gm.Events.gameHasBeenInitialized) or game.isEventFired(gm.Events.buttonWasPressed)))
            return;
        const dungeon = game.getComponents(gm.Dungeon)[0];
        try game.runtime.drawDungeon(&dungeon);
    }
};

test {
    std.testing.refAllDecls(@This());
}
