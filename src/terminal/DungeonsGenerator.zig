const std = @import("std");
const ecs = @import("ecs");
const gm = @import("game");
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
    entities_provider: ecs.EntitiesProvider,
    runtime: gm.AnyRuntime,
    render: gm.Render,
    level: gm.Level,

    pub fn init(runtime: gm.AnyRuntime) DungeonsGenerator {
        return .{
            .runtime = runtime,
            .render = gm.Render.init(runtime, gm.WHOLE_DUNG_ROWS, gm.WHOLE_DUNG_COLS),
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
        self.level = try gm.Level.generate(
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
        if (btn.code & gm.Buttons.A > 0) {
            const seed = std.crypto.random.int(u64);
            self.level.deinit();
            self.entities_provider = .{};
            try self.generate(seed);
        }
    }
};
