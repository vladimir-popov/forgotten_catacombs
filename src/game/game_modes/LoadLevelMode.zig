//! In this mode the current level is saving to the file and a new one either generating or
//! loading from file.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ps = g.persistance;

const log = std.log.scoped(.load_level_mode);

const Percent = u8;

const Process = union(enum) {
    saving: ps.Saving,
    loading: ps.Loading,
    generating: GeneratingLevel,
    done,
};

const GeneratingLevel = struct {
    // How many times try to generate a new level before panic
    pub const max_attempts = 10;

    /// PRNG based on the global game session's seed and level's depth
    prng: std.Random.DefaultPrng,
    attempt: u8 = 0,

    fn progress(self: GeneratingLevel) Percent {
        return self.attempt * 10;
    }

    fn incrementProgress(self: *GeneratingLevel) !void {
        self.attempt += 1;
        if (self.attempt > max_attempts) {
            log.err("Generating level has been failed after {d} attempts", .{self.attempt - 1});
            return error.GeneratingLevelFailed;
        }
    }
};

const Self = @This();

session: *g.GameSession,
new_depth: u8,
from_ladder: c.Ladder,
is_new_level: bool,
process: Process,

pub fn loadOrGenerateLevel(session: *g.GameSession, from_ladder: c.Ladder) !Self {
    const new_depth = switch (from_ladder.direction) {
        .up => session.level.depth - 1,
        .down => session.level.depth + 1,
    };
    log.debug(
        \\
        \\--------------------
        \\Moving {s} from the level {d} to {d} (max depth is {d})
        \\--------------------
    ,
        .{ @tagName(from_ladder.direction), session.level.depth, new_depth, session.max_depth },
    );
    return .{
        .session = session,
        .new_depth = new_depth,
        .from_ladder = from_ladder,
        .is_new_level = new_depth > session.max_depth,
        .process = .{ .saving = try ps.Saving.saveSession(session) },
    };
}

pub fn deinit(self: *Self) void {
    switch (self.process) {
        .saving => self.process.saving.deinit(),
        .loading => self.process.loading.deinit(),
        else => {},
    }
    log.debug("Level {d} is ready.", .{self.new_depth});
}

pub fn tick(self: *Self) !void {
    switch (self.process) {
        .saving => {
            if (!try self.process.saving.tick()) {
                self.process.saving.deinit();
                self.process = if (self.is_new_level)
                    .{ .generating = .{ .prng = std.Random.DefaultPrng.init(self.session.seed + self.new_depth) } }
                else
                    .{ .loading = ps.Loading.loadLevel(self.session, self.new_depth) };
            }
            errdefer self.process.saving.deinit();
        },
        .loading => {
            if (!try self.process.loading.tick()) {
                self.process.loading.deinit();
                self.process = .done;
                // self.deinit will happen inside this function:
                try self.session.playerMovedToLevel();
            }
            errdefer self.process.loading.deinit();
        },
        .generating => |*generating| {
            try self.draw();
            const seed = generating.prng.next();
            const maybe_level = try g.Level.tryGenerateNew(
                self.session.arena.allocator(),
                &self.session.registry,
                self.session.player,
                self.new_depth,
                self.from_ladder,
                seed,
            );
            if (maybe_level) |level| {
                self.session.level = level;
                self.process = .done;
                try self.session.playerMovedToLevel();
            } else {
                try generating.incrementProgress();
            }
        },
        .done => unreachable,
    }
}

fn draw(self: Self) !void {
    //        |
    // Generat|ing XXX%
    //        |
    if (self.process.generating.attempt == 0) {
        try self.session.render.drawTextWithAlign(
            10,
            "Generating",
            .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 - 7 },
            .normal,
            .left,
        );
    }
    var buf: [5]u8 = undefined;
    try self.session.render.drawTextWithAlign(
        buf.len,
        try std.fmt.bufPrint(&buf, " {d:3}%", .{self.process.generating.progress()}),
        .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 + 3 },
        .normal,
        .left,
    );
}
