const std = @import("std");
const g = @import("game");
const p = g.primitives;
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

    var runtime = try TtyRuntime.TtyRuntime(g.Dungeon.ROWS + 2, g.Dungeon.COLS + 2).init(alloc, false, false, false);
    defer runtime.deinit();

    var generator = try DungeonsGenerator.init(alloc, runtime.runtime());
    defer generator.deinit();

    try generator.generate(seed);
    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    runtime: g.Runtime,
    render: g.Render,
    viewport: g.Viewport,
    level: g.Level = undefined,
    level_arena: std.heap.ArenaAllocator,
    draw_dungeon: bool = true, // if false the map should be drawn

    pub fn init(alloc: std.mem.Allocator, runtime: g.Runtime) !DungeonsGenerator {
        return .{
            .runtime = runtime,
            .render = try g.Render.init(alloc, runtime, isVisible),
            .viewport = g.Viewport.init(g.Dungeon.ROWS, g.Dungeon.COLS),
            .level_arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: *DungeonsGenerator) void {
        self.level_arena.deinit();
        self.render.deinit();
    }

    fn isVisible(_: g.Level, _: p.Point) g.Render.Visibility {
        return .visible;
    }

    fn generate(self: *DungeonsGenerator, seed: u64) !void {
        log.info("\n====================\nGenerate level with seed {d}\n====================\n", .{seed});
        const entrance = 0;
        _ = self.level_arena.reset(.retain_capacity);
        try self.level.generate(
            self.level_arena.allocator(),
            seed,
            0,
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
            try self.render.drawDungeon(self.level, self.viewport);
            try self.render.drawSprites(self.level, self.viewport, null);
        } else {}
    }

    fn handleInput(self: *DungeonsGenerator) !bool {
        const btn = try self.runtime.readPushedButtons() orelse return false;
        if (btn.game_button == .a) {
            const seed = std.crypto.random.int(u64);
            try self.generate(seed);
        }
        if (btn.game_button == .b) {
            self.draw_dungeon = !self.draw_dungeon;
            try self.render.clearDisplay();
        }
        return true;
    }
};
