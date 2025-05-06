const std = @import("std");
const g = @import("game");
const p = g.primitives;
const tty = @import("tty.zig");

const Args = @import("Args.zig");
const Logger = @import("Logger.zig");
const TtyRuntime = @import("TtyRuntime.zig");

pub const std_options: std.Options = .{
    .logFn = Logger.writeLog,
    .log_level = .info,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .render, .level = .debug },
        // .{ .scope = .levels, .level = .debug },
        // .{ .scope = .level, .level = .debug },
        // .{ .scope = .dungeon, .level = .debug },
    },
};

const log = std.log.scoped(.DungeonsGenerator);

const DungeonType = enum { first, dungeon, cave };

pub fn main() !void {
    const seed = try Args.int(u64, "seed") orelse std.crypto.random.int(u64);
    var dungeon_type: DungeonType = .dungeon;
    if (Args.str("type")) |arg_value| {
        if (std.mem.eql(u8, @tagName(.first), arg_value)) {
            dungeon_type = .first;
        }
        if (std.mem.eql(u8, @tagName(.dungeon), arg_value)) {
            dungeon_type = .dungeon;
        }
        if (std.mem.eql(u8, @tagName(.cave), arg_value)) {
            dungeon_type = .cave;
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var runtime = try TtyRuntime.TtyRuntime(g.DUNGEON_ROWS + 2, g.DUNGEON_COLS + 2).init(
        arena.allocator(),
        false,
        false,
        false,
    );
    defer runtime.deinit();

    var generator: DungeonsGenerator = undefined;
    try generator.init(&arena, runtime.runtime(), dungeon_type);
    try generator.generate(seed);
    try runtime.run(&generator);
}

const DungeonsGenerator = struct {
    alloc: std.mem.Allocator,
    runtime: g.Runtime,
    render: g.Render,
    viewport: g.Viewport,
    dungeon_type: DungeonType,
    level: g.Level,

    pub fn init(
        self: *DungeonsGenerator,
        arena: *std.heap.ArenaAllocator,
        runtime: g.Runtime,
        dungeon_type: DungeonType,
    ) !void {
        self.* = .{
            .alloc = arena.allocator(),
            .runtime = runtime,
            .viewport = g.Viewport.init(g.DUNGEON_ROWS, g.DUNGEON_COLS),
            .dungeon_type = dungeon_type,
            .level = undefined,
            .render = undefined,
        };
        try self.render.init(self.alloc, runtime, g.DUNGEON_ROWS, g.DUNGEON_COLS);
    }

    fn generate(self: *DungeonsGenerator, seed: u64) !void {
        log.info("\n====================\nGenerate level with seed {d}\n====================\n", .{seed});
        const player = g.entities.player(self.alloc);
        switch (self.dungeon_type) {
            .first => try g.Levels.firstLevel(&self.level, self.alloc, player, true),
            .cave => try g.Levels.cave(
                &self.level,
                self.alloc,
                seed,
                0,
                player,
                .{ .direction = .down, .id = 0, .target_ladder = 1 },
            ),
            else => try g.Levels.catacomb(
                &self.level,
                self.alloc,
                seed,
                0,
                player,
                .{ .direction = .down, .id = 0, .target_ladder = 1 },
            ),
        }
        self.level.visibility_strategy = showAll;
        try self.render.clearDisplay();
        try self.draw();
    }

    fn showAll(_: *const g.Level, _: p.Point) g.Render.Visibility {
        return .visible;
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        if (!try self.handleInput()) return;
        try self.draw();
    }

    inline fn draw(self: *DungeonsGenerator) !void {
        try self.render.drawLevelOnly(self.viewport, &self.level);
    }

    fn handleInput(self: *DungeonsGenerator) !bool {
        const btn = try self.runtime.readPushedButtons() orelse return false;
        if (btn.game_button == .a) {
            self.level.deinit();
            const seed = std.crypto.random.int(u64);
            try self.generate(seed);
        }
        return true;
    }
};
