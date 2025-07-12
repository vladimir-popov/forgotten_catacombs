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
    try self.draw();

    switch (self.process) {
        .saving => |*saving| {
            switch (saving.progress) {
                .inited => {
                    saving.writer = Writer.init(&self.session.registry, saving.file_writer.writer());
                    try saving.writer.beginObject();
                    try saving.writer.writeSeed(self.session.level.dungeon.seed);
                    saving.progress = .seed_saved;
                },
                .seed_saved => {
                    try saving.writer.writeLevelEntities(self.session.level.entities.items);
                    saving.progress = .entities_saved;
                },
                .entities_saved => {
                    try saving.writer.writeVisitedPlaces(self.session.level.visited_places);
                    saving.progress = .visited_places_saved;
                },
                .visited_places_saved => {
                    try saving.writer.writeRememberedObjects(self.session.level.remembered_objects);
                    saving.progress = .remembered_objects_saved;
                },
                .remembered_objects_saved => {
                    try saving.writer.endObject();
                    try self.removeEntitiesOfTheLevel();
                    _ = self.session.level.arena.deinit();
                    saving.deinit();
                    log.debug("Saving is completed", .{});
                    self.process = if (self.is_new_level)
                        try self.beginGenerating()
                    else
                        try self.beginLoading();
                },
            }
        },
        .loading => |*loading| {
            switch (loading.progress) {
                .inited => {
                    loading.reader = Reader.init(&self.session.registry, loading.file_reader.reader());
                    try loading.reader.beginObject();
                    const seed = try loading.reader.readSeed();
                    self.session.level = try g.Level.initEmpty(
                        self.session.arena.allocator(),
                        &self.session.registry,
                        self.session.player,
                        self.new_depth,
                        seed,
                    );
                    loading.progress = .level_inited;
                },
                .level_inited => {
                    try loading.reader.readLevelEntities(&self.session.level);
                    loading.progress = .entities_loaded;
                },
                .entities_loaded => {
                    try loading.reader.readVisitedPlaces(&self.session.level);
                    loading.progress = .visited_places_loaded;
                },
                .visited_places_loaded => {
                    try loading.reader.readRememberedObjects(&self.session.level);
                    loading.progress = .remembered_objects_loaded;
                },
                .remembered_objects_loaded => {
                    try loading.reader.endObject();
                    try self.session.level.completeInitialization(self.from_ladder.direction);
                    log.debug("Loading is completed", .{});
                    // self.deinit will happen inside this function:
                    try self.session.playerMovedToLevel();
                    return;
                },
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
                log.debug("Generating is completed", .{});
                // self.deinit will happen inside this function:
                try self.session.playerMovedToLevel();
                return;
            } else {
                try generating.incrementProgress();
            }
        },
    }
}

fn beginSaving(session: *g.GameSession) !Process {
    var buf: [50]u8 = undefined;
    const file_path = try pathToLevelFile(&buf, session.level.depth);
    log.debug("Start saving level on depth {d} to {s}", .{ session.level.depth, file_path });
    return .{ .saving = .{ .file_writer = try session.runtime.fileWriter(file_path) } };
}

fn beginGenerating(self: *Self) !Process {
    const seed = self.session.seed + self.new_depth;
    log.debug("Start generating a new level on depth {d} with seed {d}", .{ self.new_depth, seed });
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

fn draw(self: Self) !void {
    switch (self.process) {
        .saving => |saving| {
            if (saving.progress == .inited) {
                try self.session.render.clearDisplay();
                try self.drawScereenFromScratch("Saving");
            } else try self.drawProgress(@intFromEnum(saving.progress));
        },
        .loading => |loading| {
            if (loading.progress == .inited)
                try self.drawScereenFromScratch("Loading")
            else
                try self.drawProgress(@intFromEnum(loading.progress));
        },
        .generating => |generating| {
            if (generating.attempt == 0)
                try self.drawScereenFromScratch("Generating")
            else
                try self.drawProgress(generating.progress());
        },
    }
    // var tmp: usize = 0;
    // for (0..100000000) |i| {
    //     tmp += i;
    // }
}

fn drawScereenFromScratch(self: Self, label: []const u8) !void {
    const vertical_middle = g.DISPLAY_ROWS / 2;
    try self.session.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        label,
        .{ .row = vertical_middle - 1, .col = 1 },
        .normal,
        .center,
    );
    try self.drawProgress(0);
}

fn drawProgress(self: Self, percent: u8) !void {
    var buf: [4]u8 = undefined;
    const vertical_middle = g.DISPLAY_ROWS / 2;
    try self.session.render.drawTextWithAlign(
        g.DISPLAY_COLS,
        try std.fmt.bufPrint(&buf, "{d:3}%", .{percent}),
        .{ .row = vertical_middle, .col = 1 },
        .normal,
        .center,
    );
}

const SavingLevel = struct {
    const Progress = enum(u8) {
        inited = 0,
        seed_saved = 10,
        entities_saved = 50,
        visited_places_saved = 70,
        remembered_objects_saved = 90,
    };
    file_writer: g.Runtime.FileWriter,
    progress: Progress = .inited,
    writer: Writer = undefined,

    fn deinit(self: *SavingLevel) void {
        if (self.progress != .inited) self.writer.deinit();
        log.debug("Closing save file", .{});
        self.file_writer.deinit();
    }
};

const LoadingLevel = struct {
    const Progress = enum(u8) {
        inited = 0,
        level_inited = 10,
        entities_loaded = 50,
        visited_places_loaded = 70,
        remembered_objects_loaded = 90,
    };

    file_reader: g.Runtime.FileReader,
    progress: Progress = .inited,
    reader: Reader = undefined,

    pub fn deinit(self: *LoadingLevel) void {
        if (self.progress != .inited) self.reader.deinit();
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
