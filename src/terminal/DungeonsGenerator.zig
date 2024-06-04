const std = @import("std");
const ecs = @import("ecs");
const game = @import("game");
const tty = @import("tty.zig");

const Logger = @import("Logger.zig");
const Runtime = @import("Runtime.zig");

pub const std_options = .{
    .logFn = Logger.writeLog,
};

const log = std.log.scoped(.DungeonsGenerator);

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const seed = if (args.next()) |arg|
        try std.fmt.parseInt(u64, arg, 10)
    else
        std.crypto.random.int(u64);
    log.debug("The random seed is {d}", .{seed});
    var rnd = std.Random.DefaultPrng.init(seed);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();

    var runtime = try Runtime.init(alloc, rnd.random(), &arena);
    defer runtime.deinit();
    var universe = try DungeonsGenerator.init(runtime.any());
    defer universe.deinit();

    try runtime.run(&universe);
}

const Components = union {
    dungeon: game.components.Dungeon,
    screen: game.components.Screen,
};

const DungeonsGenerator = struct {
    pub const Universe = ecs.Universe(Components, game.AnyRuntime);
    const Dungeon = game.components.Dungeon;

    pub fn init(runtime: game.AnyRuntime) !Universe {
        var universe: Universe = Universe.init(runtime.alloc, runtime);

        // Generate dungeon:
        const dungeon = try Dungeon.bspGenerate(
            universe.runtime.alloc,
            universe.runtime.rand,
        );
        // The screen to see whole dungeon:
        const screen = game.components.Screen.init(Dungeon.Region.rows, Dungeon.Region.cols, Dungeon.Region);

        _ = universe.newEntity()
            .withComponent(game.components.Dungeon, dungeon)
            .withComponent(game.components.Screen, screen);

        // Initialize systems:
        universe.registerSystem(handleInput);
        universe.registerSystem(render);

        return universe;
    }

    fn handleInput(universe: *Universe) anyerror!void {
        const btn = try universe.runtime.readButton() orelse return;

        if (btn & game.Button.A > 0) {
            var entities = universe.entitiesIterator();
            while (entities.next()) |entity| {
                if (universe.getComponent(entity, game.components.Dungeon)) |_| {
                    universe.removeComponentFromEntity(entity, game.components.Dungeon);
                    const seed = universe.runtime.rand.int(u64);
                    log.debug("The random seed is {d}", .{seed});
                    var rnd = std.Random.DefaultPrng.init(seed);
                    const dungeon = try game.components.Dungeon.bspGenerate(
                        universe.runtime.alloc,
                        rnd.random(),
                    );
                    universe.addComponent(entity, game.components.Dungeon, dungeon);
                }
            }
        }
    }

    fn render(universe: *Universe) anyerror!void {
        const dungeon = &universe.getComponents(game.components.Dungeon)[0];
        const screen = &universe.getComponents(game.components.Screen)[0];
        try universe.runtime.drawDungeon(screen, dungeon);
    }
};
