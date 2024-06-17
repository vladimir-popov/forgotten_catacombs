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

    var generator = try DungeonsGenerator.init(runtime.any());
    defer generator.deinit();

    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    runtime: game.AnyRuntime,
    screen: game.Screen,
    dungeon: *game.Dungeon,

    pub fn init(runtime: game.AnyRuntime) !DungeonsGenerator {
        return .{
            .runtime = runtime,
            // Generate dungeon:
            .dungeon = try game.Dungeon.createRandom(runtime.alloc, runtime.rand),
            // The screen to see whole dungeon:
            .screen = game.Screen.init(
                game.Dungeon.Region.rows,
                game.Dungeon.Region.cols,
                game.Dungeon.Region,
            ),
        };
    }

    pub fn deinit(self: *DungeonsGenerator) void {
        self.dungeon.destroy();
        self.screen.deinit();
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
            self.dungeon.destroy();
            self.dungeon = try game.Dungeon.createRandom(
                self.runtime.alloc,
                rnd.random(),
            );
        }
    }

    fn render(self: *DungeonsGenerator) anyerror!void {
        try self.runtime.drawDungeon(&self.screen, self.dungeon);
    }
};
