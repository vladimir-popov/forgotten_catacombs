const std = @import("std");
const g = @import("game");
const tty = @import("tty.zig");

const Logger = @import("Logger.zig");
const TtyRuntime = @import("TtyRuntime.zig");

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

    var runtime = try TtyRuntime.init(alloc, false, false, false);
    defer runtime.deinit();

    var generator = try DungeonsGenerator.init(runtime.runtime());
    defer generator.deinit();

    try generator.generate(seed);
    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    runtime: g.Runtime,
    render: g.render.Render(g.Dungeon.ROWS + 1, g.Dungeon.COLS + 1),
    level: g.Level,
    draw_dungeon: bool = true, // if false the map should be drawn

    pub fn init(runtime: g.Runtime) !DungeonsGenerator {
        return .{
            .runtime = runtime,
            .render = g.render.Render(g.Dungeon.ROWS + 1, g.Dungeon.COLS + 1).init(runtime),
            .level = try g.Level.init(runtime.alloc, 0),
        };
    }

    pub fn deinit(self: *DungeonsGenerator) void {
        self.level.deinit();
    }

    fn generate(self: *DungeonsGenerator, seed: u64) !void {
        log.info("\n====================\nGenerate level with seed {d}\n====================\n", .{seed});
        const entrance = 0;
        try self.level.generate(
            seed,
            g.entities.Player,
            entrance,
            null,
            .down,
        );
        try self.level.movePlayerToLadder(entrance);
        try self.render.clearDisplay();
        try self.draw();
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        if (!try self.handleInput()) return;
        try self.draw();
    }

    fn draw(self: *DungeonsGenerator) !void {
        if (self.draw_dungeon) {
            try self.render.drawDungeon(self.level.dungeon);
            try self.render.drawSprites(self.level, null);
        } else {}
    }

    fn handleInput(self: *DungeonsGenerator) !bool {
        const btn = try self.runtime.readPushedButtons() orelse return false;
        if (btn.game_button == .a) {
            const seed = std.crypto.random.int(u64);
            self.level.deinit();
            self.level = try g.Level.init(self.runtime.alloc, 0);
            try self.generate(seed);
        }
        if (btn.game_button == .b) {
            self.draw_dungeon = !self.draw_dungeon;
            try self.render.clearDisplay();
        }
        return true;
    }
};
