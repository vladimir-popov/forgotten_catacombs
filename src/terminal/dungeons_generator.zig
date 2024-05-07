const std = @import("std");
const ecs = @import("ecs");
const game = @import("game");
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
    var universe = try DungeonsGenerator.init(runtime.any());
    defer universe.deinit();

    try runtime.run(&universe);
}

const Components = union(enum) {
    dungeon: game.Dungeon,

    fn deinitAll(components: Components) void {
        switch (components) {
            .dungeon => components.dungeon.deinit(),
        }
    }
};

const DungeonsGenerator = struct {
    const Self = @This();
    pub const Universe = ecs.Universe(Components, game.Events, game.AnyRuntime);

    pub fn init(runtime: game.AnyRuntime) !Universe {
        var universe: Universe = Universe.init(runtime.alloc, runtime, Components.deinitAll);

        // Generate dungeon:
        const dungeon = try game.Dungeon.bspGenerate(
            universe.runtime.alloc,
            universe.runtime.rand,
            game.ROWS,
            game.COLS,
        );

        const entity = universe.newEntity();
        entity.addComponent(game.Dungeon, dungeon);

        // Initialize systems:
        universe.registerSystem(handleInput);
        universe.registerSystem(render);

        universe.fireEvent(game.Events.gameHasBeenInitialized);
        return universe;
    }

    fn handleInput(universe: *Universe) anyerror!void {
        const btn = try universe.runtime.readButton() orelse return;

        universe.fireEvent(game.Events.buttonWasPressed);

        if (btn & game.Button.A > 0) {
            var entities = universe.entitiesIterator();
            while (entities.next()) |entity| {
                if (universe.getComponent(entity, game.Dungeon)) |_| {
                    universe.removeComponentFromEntity(entity, game.Dungeon);
                    const dungeon = try game.Dungeon.bspGenerate(
                        universe.runtime.alloc,
                        universe.runtime.rand,
                        game.ROWS,
                        game.COLS,
                    );
                    universe.addComponent(entity, game.Dungeon, dungeon);
                }
            }
        }
    }

    fn render(universe: *Universe) anyerror!void {
        if (!(universe.isEventFired(game.Events.gameHasBeenInitialized) or universe.isEventFired(game.Events.buttonWasPressed)))
            return;
        const dungeon = universe.getComponents(game.Dungeon)[0];
        try universe.runtime.drawDungeon(&dungeon);
    }
};

test {
    std.testing.refAllDecls(@This());
}
