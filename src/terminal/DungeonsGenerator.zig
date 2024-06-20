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

    var runtime = try Runtime.init(alloc, rnd.random(), false);
    defer runtime.deinit();

    var generator = try DungeonsGenerator.create(runtime.any());
    defer generator.destroy();

    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    runtime: game.AnyRuntime,
    entities: ecs.EntitiesManager,
    components: ecs.ComponentsManager(game.Components),
    screen: game.Screen,
    dungeon: *game.Dungeon,

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
        try self.generate(runtime.rand);
        return self;
    }

    // we use custom rand here to be able to predict the seed
    fn generate(self: *DungeonsGenerator, rand: std.Random) !void {
        self.entities = try ecs.EntitiesManager.init(self.runtime.alloc);
        self.components = try ecs.ComponentsManager(game.Components).init(self.runtime.alloc);
        self.dungeon = try game.Dungeon.createRandom(self.runtime.alloc, rand);
        _ = try game.GameSession.initPlayer(&self.entities, &self.components, self.dungeon.randomPlaceInRoom());
    }

    pub fn destroy(self: *DungeonsGenerator) void {
        self.dungeon.destroy();
        self.components.deinit();
        self.entities.deinit();
        self.screen.deinit();
        self.runtime.alloc.destroy(self);
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        try self.handleInput();
        try self.render();
    }

    fn handleInput(self: *DungeonsGenerator) anyerror!void {
        const btn = try self.runtime.readButtons() orelse return;
        if (btn.code & game.AnyRuntime.Buttons.A > 0) {
            const seed = self.runtime.rand.int(u64);
            log.debug("The random seed is {d}", .{seed});
            var rnd = std.Random.DefaultPrng.init(seed);
            try self.regenerate(rnd.random());
        }
    }

    fn regenerate(self: *DungeonsGenerator, rand: std.Random) !void {
        self.dungeon.destroy();
        self.entities.deinit();
        self.components.deinit();
        try self.generate(rand);
    }

    fn render(self: *DungeonsGenerator) anyerror!void {
        try self.runtime.drawDungeon(&self.screen, self.dungeon);
        for (self.components.getAll(game.Position)) |*position| {
            if (self.screen.region.containsPoint(position.point)) {
                for (self.components.getAll(game.Sprite)) |*sprite| {
                    try self.runtime.drawSprite(&self.screen, sprite, position);
                }
            }
        }
    }
};
