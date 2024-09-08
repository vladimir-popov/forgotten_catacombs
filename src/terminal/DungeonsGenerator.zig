const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const Logger = @import("Logger.zig");
const Runtime = @import("TtyRuntime.zig");

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

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    var runtime = try Runtime.init(alloc, false, false);
    defer runtime.deinit();

    var generator = DungeonsGenerator.init(runtime.any());
    defer generator.deinit();

    try generator.generate(seed);
    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    entities_provider: g.ecs.EntitiesProvider,
    runtime: g.AnyRuntime,
    render: g.Render,
    level: g.Level,

    pub fn init(runtime: g.AnyRuntime) DungeonsGenerator {
        return .{
            .runtime = runtime,
            .render = g.Render.init(runtime),
            .entities_provider = .{},
            .level = undefined,
        };
    }

    pub fn deinit(self: *DungeonsGenerator) void {
        self.level.deinit();
    }

    fn generate(self: *DungeonsGenerator, seed: u64) !void {
        log.info("\n====================\nGenerate level with seed {d}\n====================\n", .{seed});
        const entrance = self.entities_provider.newEntity();
        self.level = try g.Level.generate(
            self.runtime.alloc,
            seed,
            self.entities_provider.newEntity(),
            self.entities_provider,
            0,
            entrance,
            null,
            .down,
        );
        try self.level.movePlayerToLadder(entrance);
        try self.render.clearDisplay();
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        try self.handleInput();
        try self.render.drawDungeon(self.level.dungeon);
        try self.render.drawSprites(self.level, null);
    }

    fn handleInput(self: *DungeonsGenerator) anyerror!void {
        const btn = try self.runtime.readPushedButtons() orelse return;
        if (btn.game_button == .a) {
            const seed = std.crypto.random.int(u64);
            self.level.deinit();
            self.entities_provider = .{};
            try self.generate(seed);
        }
    }
};
