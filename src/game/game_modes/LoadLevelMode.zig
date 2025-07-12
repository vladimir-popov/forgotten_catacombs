//! In this mode the current level is saving to the file and a new one either generating or
//! loading from file.
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;

const log = std.log.scoped(.load_level_mode);

const Percent = u8;

const Reader = g.persistance.Reader(g.Runtime.FileReader.Reader);
const Writer = g.persistance.Writer(g.Runtime.FileWriter.Writer);

const Process = union(enum) {
    saving: SavingLevel,
    loading: LoadingLevel,
    generating: GeneratingLevel,
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
        .process = try beginSaving(session),
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
    try self.drawLoadingScreen();

    if (self.isCompleted()) {
        // self.deinit will happen inside this function:
        try self.session.playerMovedToLevel();
        return;
    }

    switch (self.process) {
        .saving => |*saving| {
            if (saving.writer) |*writer| {
                try writer.writeLevelEntities(self.session.level.entities.items);
                try writer.writeVisitedPlaces(self.session.level.visited_places);
                try writer.writeRememberedObjects(self.session.level.remembered_objects);
                try writer.endObject();
                saving.progress = 100;
                log.debug("Saving is completed", .{});
            } else {
                saving.writer = Writer.init(&self.session.registry, saving.file_writer.writer());
                try saving.writer.?.beginObject();
                try saving.writer.?.writeSeed(self.session.level.dungeon.seed);
            }
            if (saving.progress == 100) {
                try self.removeEntitiesOfTheLevel();
                _ = self.session.level.arena.deinit();
                saving.deinit();
                self.process = if (self.is_new_level)
                    try self.beginGenerating()
                else
                    try self.beginLoading();
            }
        },
        .loading => |*loading| {
            if (loading.reader) |*reader| {
                try reader.readLevelEntities(&self.session.level);
                try reader.readVisitedPlaces(&self.session.level);
                try reader.readRememberedObjects(&self.session.level);
                try reader.endObject();
                loading.progress = 100;
                log.debug("Loading is completed", .{});
            } else {
                loading.reader = Reader.init(&self.session.registry, loading.file_reader.reader());
                try loading.reader.?.beginObject();
                const seed = try loading.reader.?.readSeed();
                self.session.level = try g.Level.initEmpty(
                    self.session.arena.allocator(),
                    &self.session.registry,
                    self.session.player,
                    self.new_depth,
                    seed,
                );
            }
            if (loading.progress == 100) {
                try self.session.level.completeInitialization(self.from_ladder.direction);
            }
        },
        .generating => |*generating| {
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
                generating.attempt = GeneratingLevel.max_attempts;
            } else {
                try generating.incrementProgress();
            }
        },
    }
}

fn isCompleted(self: Self) bool {
    return switch (self.process) {
        .saving => false,
        .loading => self.process.loading.progress == 100,
        .generating => self.process.generating.attempt == GeneratingLevel.max_attempts,
    };
}

fn beginSaving(session: *g.GameSession) !Process {
    var buf: [50]u8 = undefined;
    const file_path = try pathToLevelFile(&buf, session.level.depth);
    log.debug("Start saving level on depth {d} to {s}", .{ session.level.depth, file_path });
    return .{ .saving = .{ .file_writer = try session.runtime.fileWriter(file_path) } };
}

fn beginGenerating(self: *Self) !Process {
    const seed = self.session.seed + self.new_depth;
    log.debug("Start generating a new level on depth {d} with seed {d}", .{self.new_depth, seed});
    return .{ .generating = .{ .prng = std.Random.DefaultPrng.init(seed) } };
}

fn beginLoading(self: *Self) !Process {
    var buf: [50]u8 = undefined;
    const file_path = try pathToLevelFile(&buf, self.new_depth);
    log.debug("Start loading a level on depth {d} from {s}", .{ self.new_depth, file_path });
    return .{ .loading = .{ .file_reader = try self.session.runtime.fileReader(file_path) } };
}

/// Removes all entities belong to the level from the registry.
/// It should be done before init a new level and deinit previous one.
fn removeEntitiesOfTheLevel(self: Self) !void {
    for (self.session.level.entities.items) |entity| {
        if (!entity.eql(self.session.player))
            try self.session.registry.removeEntity(entity);
    }
}

fn pathToLevelFile(buf: []u8, depth: u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "level_{d}.json", .{depth});
}

fn drawLoadingScreen(self: Self) !void {
    _ = self;
}

const SavingLevel = struct {
    file_writer: g.Runtime.FileWriter,
    writer: ?Writer = null,
    progress: Percent = 0,

    pub fn deinit(self: *SavingLevel) void {
        if (self.writer) |*writer| writer.deinit();
        log.debug("Closing save file", .{});
        self.file_writer.deinit();
    }
};

const LoadingLevel = struct {
    file_reader: g.Runtime.FileReader,
    reader: ?Reader = null,
    progress: Percent = 0,

    pub fn deinit(self: *LoadingLevel) void {
        if (self.reader) |*reader| reader.deinit();
        log.debug("Closing loaded file", .{});
        self.file_reader.deinit();
    }
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
