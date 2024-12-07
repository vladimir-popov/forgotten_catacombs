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
        // .{ .scope = .ai, .level = .debug },
        // .{ .scope = .play_mode, .level = .debug },
        // .{ .scope = .game_session, .level = .debug },
        // .{ .scope = .cellural_automata, .level = .debug },
        // .{ .scope = .action_system, .level = .debug },
    },
};

const log = std.log.scoped(.DungeonsGenerator);

const DungeonType = enum { first, dungeon, cellural };

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
        if (std.mem.eql(u8, @tagName(.cellural), arg_value)) {
            dungeon_type = .cellural;
        }
    }

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("MEMORY LEAK DETECTED!");
    const alloc = gpa.allocator();

    var runtime = try TtyRuntime.TtyRuntime(g.DUNGEON_ROWS + 2, g.DUNGEON_COLS + 2).init(alloc, false, false, false);
    defer runtime.deinit();

    var generator = try DungeonsGenerator.init(alloc, runtime.runtime(), dungeon_type);
    defer generator.deinit();

    try generator.generate(seed);
    try runtime.run(&generator);
}

fn showAll(_: *anyopaque, _: p.Point) g.Render.Visibility {
    return .visible;
}

const DungeonsGenerator = struct {
    runtime: g.Runtime,
    render: g.Render,
    dungeon_type: DungeonType,
    level: g.Level = undefined,
    level_arena: std.heap.ArenaAllocator,
    draw_dungeon: bool = true, // if false the map should be drawn

    pub fn init(alloc: std.mem.Allocator, runtime: g.Runtime, dungeon_type: DungeonType) !DungeonsGenerator {
        return .{
            .runtime = runtime,
            .render = try g.Render.init(
                alloc,
                runtime,
                .{ .context = undefined, .isVisible = showAll },
                g.DUNGEON_ROWS,
                g.DUNGEON_COLS,
            ),
            .dungeon_type = dungeon_type,
            .level_arena = std.heap.ArenaAllocator.init(alloc),
        };
    }

    pub fn deinit(self: *DungeonsGenerator) void {
        self.level_arena.deinit();
        self.render.deinit();
    }

    fn generate(self: *DungeonsGenerator, seed: u64) !void {
        log.info("\n====================\nGenerate level with seed {d}\n====================\n", .{seed});
        _ = self.level_arena.reset(.retain_capacity);
        switch (self.dungeon_type) {
            .first => try self.level.generateFirstLevel(&self.level_arena, g.entities.Player, true),
            .cellural => try self.level.generateCave(
                &self.level_arena,
                seed,
                0,
                g.entities.Player,
                .{ .direction = .down, .id = 0, .target_ladder = 1 },
            ),
            else => try self.level.generateCatacomb(
                &self.level_arena,
                seed,
                0,
                g.entities.Player,
                .{ .direction = .down, .id = 0, .target_ladder = 1 },
            ),
        }
        try self.render.clearDisplay();
        try self.draw();
    }

    pub fn tick(self: *DungeonsGenerator) !void {
        if (!try self.handleInput()) return;
        try self.draw();
    }

    fn draw(self: *DungeonsGenerator) !void {
        if (self.draw_dungeon) {
            try self.render.drawLevelOnly(self.level);
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
