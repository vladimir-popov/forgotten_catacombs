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
    log.info("The random seed is {d}", .{seed});
    var rnd = std.Random.DefaultPrng.init(seed);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    var runtime = try Runtime.init(alloc, rnd.random(), false);
    defer runtime.deinit();

    var generator = try DungeonsGenerator.create(runtime.any());
    defer generator.destroy();

    try runtime.run(generator);
}

const DungeonsGenerator = struct {
    runtime: game.AnyRuntime,
    entities: ecs.EntitiesManager,
    components: ecs.ComponentsManager(game.Components),
    screen: game.Screen,
    dungeon: *game.Dungeon,
    query: ecs.ComponentsQuery(game.Components) = undefined,

    pub fn create(runtime: game.AnyRuntime) !*DungeonsGenerator {
        const self = try runtime.alloc.create(DungeonsGenerator);
        self.* = .{
            .runtime = runtime,
            // The screen to see whole dungeon:
            .screen = game.Screen.init(
                game.Dungeon.Region.rows,
                game.Dungeon.Region.cols,
                game.Dungeon.Region,
            ),
            .entities = undefined,
            .components = undefined,
            .dungeon = undefined,
        };
        self.query = .{ .entities = &self.entities, .components = &self.components };
        try self.generate(runtime.rand);
        return self;
    }

    pub fn destroy(self: *DungeonsGenerator) void {
        self.dungeon.destroy();
        self.components.deinit();
        self.entities.deinit();
        self.screen.deinit();
        self.runtime.alloc.destroy(self);
    }

    // we use custom rand here to be able to predict the seed
    fn generate(self: *DungeonsGenerator, rand: std.Random) !void {
        self.entities = try ecs.EntitiesManager.init(self.runtime.alloc);
        self.components = try ecs.ComponentsManager(game.Components).init(self.runtime.alloc);
        self.dungeon = try game.Dungeon.createRandom(self.runtime.alloc, rand);
        _ = try game.GameSession.initLevel(self.dungeon, &self.entities, &self.components);
    }

    fn regenerate(self: *DungeonsGenerator, rand: std.Random) !void {
        self.dungeon.destroy();
        self.entities.deinit();
        self.components.deinit();
        try self.generate(rand);
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        try self.handleInput();
        try self.render();
    }

    fn handleInput(self: *DungeonsGenerator) anyerror!void {
        const btn = try self.runtime.readPushedButtons() orelse return;
        if (btn.code & game.Buttons.A > 0) {
            const seed = self.runtime.rand.int(u64);
            log.info("The random seed is {d}", .{seed});
            var rnd = std.Random.DefaultPrng.init(seed);
            try self.regenerate(rnd.random());
        }
    }

    fn render(self: *DungeonsGenerator) anyerror!void {
        try self.runtime.clearDisplay();
        try self.runtime.drawDungeon(&self.screen, self.dungeon);
        var itr = self.query.get2(game.Position, game.Sprite);
        while (itr.next()) |tuple| {
            const position = tuple[1];
            const sprite = tuple[2];
            if (self.screen.region.containsPoint(position.point)) {
                try self.runtime.drawSprite(&self.screen, sprite, position, .normal);
            }
        }
    }
};
