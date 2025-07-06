//! In this mode the current level is saving to the file and a new one either generating or
//! loading from file.
const std = @import("std");
const g = @import("../game_pkg.zig");

const log = std.log.scoped(.load_level_mode);

const Percent = u8;

const SavingLevel = struct {
    writer: g.Runtime.FileWriter,
    progress: Percent = 0,
};

const LoadingLevel = struct {
    reader: g.Runtime.FileReader,
    progress: Percent = 0,
};

const GeneratingLevel = struct {
    // How many times try to generate a new level before panic
    const max_attempts = 10;

    /// PRNG based on the global game session's seed and level's depth
    prng: std.Random.DefaultPrng,
    attempt: u8 = 0,

    fn progress(self: GeneratingLevel) Percent {
        return self.attempt * 10;
    }

    fn complete(self: *GeneratingLevel) void {
        self.attempt = max_attempts;
    }

    fn incrementProgres(self: *GeneratingLevel) !void {
        self.attempt += 1;
        if (self.attempt > max_attempts) {
            log.err("Generating level has been failed after {d} attempts", .{self.attempt - 1});
            return error.GeneratingLevelFailed;
        }
    }
};

const Process = union(enum) {
    saving: SavingLevel,
    loading: LoadingLevel,
    generating: GeneratingLevel,
};

const Self = @This();

session: *g.GameSession,
new_depth: u8,
from_ladder: g.components.Ladder,
is_new_level: bool,
process: Process,

pub fn loadOrGenerateLevel(session: *g.GameSession, from_ladder: g.components.Ladder) !Self {
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
        .process = try beginSaving(session),
    };
}

pub fn deinit(self: Self) void {
    switch (self.process) {
        .saving => self.process.saving.writer.deinit(),
        .loading => self.process.loading.reader.deinit(),
        else => {},
    }
    log.debug("Level {d} is ready.", .{self.new_depth});
}

pub fn tick(self: *Self) !void {
    try self.drawLoadingScreen();

    if (self.isCompleted()) {
        try self.session.playerMovedToLevel();
        return;
    }

    switch (self.process) {
        .saving => |*process| {
            const alloc = self.session.level.arena.allocator();
            process.progress =
                try self.session.storage.saveLevel(alloc, self.session.level, process.writer, process.progress);
            if (process.progress == 100) {
                process.writer.deinit();
                self.process = if (self.is_new_level)
                    try self.beginGenerating()
                else
                    try self.beginLoading();
            }
        },
        .generating => |*process| {
            const seed = process.prng.next();
            if (try self.session.level.tryGenerateNew(self.new_depth, self.from_ladder, seed))
                process.complete()
            else
                try process.incrementProgres();
        },
        .loading => |*process| {
            process.progress =
                try self.session.storage.loadLevel(
                    &self.session.level,
                    process.reader,
                    self.from_ladder.direction,
                    process.progress,
                );
        },
    }
}

fn isCompleted(self: Self) bool {
    return switch (self.process) {
        .saving => false,
        .loading => self.process.loading.progress == 100,
        .generating => self.process.generating.progress() == 100,
    };
}

fn beginSaving(session: *g.GameSession) !Process {
    var buf: [50]u8 = undefined;
    const file_path = try pathToLevelFile(&buf, session.level.depth);
    log.debug("Start saving level on depth {d} to {s}", .{ session.level.depth, file_path });
    return .{ .saving = .{ .writer = try session.runtime.fileWriter(file_path) } };
}

fn beginGenerating(self: *Self) !Process {
    log.debug("Start generating level on depth {d}", .{self.new_depth});
    try self.removeEntitiesFromLevel();
    return .{ .generating = .{ .prng = std.Random.DefaultPrng.init(self.session.seed + self.new_depth) } };
}

fn beginLoading(self: *Self) !Process {
    var buf: [50]u8 = undefined;
    const file_path = try pathToLevelFile(&buf, self.new_depth);
    log.debug("Start loading level on depth {d} from {s}", .{ self.new_depth, file_path });
    try self.removeEntitiesFromLevel();
    return .{ .loading = .{ .reader = try self.session.runtime.fileReader(file_path) } };
}

/// Removes all entities belong to the level from the registry.
/// It should be done before init a new level and deinit previous one.
fn removeEntitiesFromLevel(self: Self) !void {
    for (self.session.level.entities.items) |entity| {
        if (!entity.eql(self.session.player))
            try self.session.entities.removeEntity(entity);
    }
}

fn pathToLevelFile(buf: []u8, depth: u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "level_{d}.json", .{depth});
}

fn drawLoadingScreen(self: Self) !void {
    _ = self;
}
