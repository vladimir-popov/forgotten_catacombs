//! In this mode the current level is saving to the file and a new one either generating or
//! This is a mode in which save/load happens.
//!
//! The purposes of this mode can be:
//!
//! - loading an existed game session;
//! - saving the current game session;
//! - generating a new level;
//! - loading a new level;
//!
//! Before load or generate a level, the current one should be saved.
//! Saving a session should not lead to the loading a level.
//!
//! ```
//! `loadSession`: load session - load level - done
//!
//! `saveSession`: save session - save level - done
//!
//!                                       load level - done
//!                                     /
//! `loadOrGenerateLevel`: save session - generate level - done
//!
//! ```
const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;
const ps = g.persistance;

const log = std.log.scoped(.save_load_mode);

const Percent = u8;

const Process = union(enum) {
    saving: Saving,
    loading: Loading,
    generating: Generating,
};

const Self = @This();

process: Process,

pub fn deinit(self: *Self) void {
    switch (self.process) {
        .saving => self.process.saving.deinit(),
        .loading => self.process.loading.deinit(),
        .generating => {},
    }
}

// the session should be preinited
pub fn loadSession(session: *g.GameSession) Self {
    return .{ .process = .{ .loading = Loading.loadSession(session) } };
}

// the session should be preinited
pub fn saveSession(session: *g.GameSession) Self {
    return .{ .process = .{ .saving = .{ .session = session, .next_process = .go_to_welcome_screen } } };
}

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
    const next: Saving.NextProcess = if (new_depth > session.max_depth)
        .{ .generate_level = .{
            .prng = std.Random.DefaultPrng.init(session.seed + new_depth),
            .depth = new_depth,
            .from_ladder = from_ladder,
        } }
    else
        .{ .load_level = .{ .depth = new_depth, .direction = from_ladder.direction } };

    return .{ .process = .{ .saving = .{ .session = session, .next_process = next } } };
}

pub fn tick(self: *Self) !void {
    switch (self.process) {
        .saving => |*saving| {
            const is_continue = saving.tick() catch |err| {
                log.err("Error on saving a level on depth {d}", .{saving.session.level.depth});
                saving.deinit();
                return err;
            };
            if (!is_continue) {
                const session = self.process.saving.session;
                log.debug("Saving completed. Next process is {s}", .{@tagName(saving.next_process)});
                switch (saving.next_process) {
                    .generate_level => |generate| {
                        saving.deinit();
                        self.process = .{
                            .generating = Generating{
                                .session = session,
                                .prng = generate.prng,
                                .depth = generate.depth,
                                .from_ladder = generate.from_ladder,
                            },
                        };
                    },
                    .load_level => |load| {
                        saving.deinit();
                        self.process = .{
                            .loading = Loading.loadLevel(session, load.depth, load.direction),
                        };
                    },
                    .go_to_welcome_screen => {
                        return error.GoToMainMenu;
                    },
                }
            }
        },
        .loading => |*loading| {
            const is_continue = loading.tick() catch |err| {
                log.err("Error on loading level on depth {d}", .{loading.level_depth});
                loading.deinit();
                return err;
            };
            if (!is_continue) {
                // the deinit will be invoked for the whole SaveLoadMode here:
                try loading.session.playerMovedToLevel();
            }
        },
        .generating => |*generating| {
            try generating.draw();
            const seed = generating.prng.next();
            log.debug(
                "Start {d} attempt to generate a level {s} on depth {d} from ladder {any}. Seed is {d}",
                .{
                    generating.attempt,
                    @tagName(generating.from_ladder.direction),
                    generating.depth,
                    generating.from_ladder,
                    seed,
                },
            );
            const is_success = try generating.session.level.tryGenerateNew(
                generating.session.player,
                generating.depth,
                generating.from_ladder,
                seed,
            );
            if (is_success) {
                try generating.session.playerMovedToLevel();
            } else {
                try generating.incrementProgress();
            }
        },
    }
}

const Generating = struct {
    // How many times try to generate a new level before panic
    pub const max_attempts = 10;

    session: *g.GameSession,
    /// PRNG based on the global game session's seed and level's depth
    prng: std.Random.DefaultPrng,
    depth: u8,
    from_ladder: c.Ladder,
    attempt: u8 = 0,

    fn progress(self: Generating) Percent {
        return self.attempt * 10;
    }

    fn incrementProgress(self: *Generating) !void {
        self.attempt += 1;
        if (self.attempt > max_attempts) {
            log.err("Generating level has been failed after {d} attempts", .{self.attempt - 1});
            return error.GeneratingLevelFailed;
        }
    }

    fn draw(self: *Generating) !void {
        //        |
        // Generat|ing XXX%
        //        |
        if (self.attempt == 0) {
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
            try std.fmt.bufPrint(&buf, " {d:3}%", .{self.progress()}),
            .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 + 3 },
            .normal,
            .left,
        );
    }
};

const Loading = struct {
    const Reader = g.persistance.Reader(g.Runtime.FileReader.Reader);

    const Progress = enum(u8) {
        session_preinited = 0,
        session_loaded = 10,
        level_inited = 20,
        entities_loaded = 70,
        visited_places_loaded = 80,
        remembered_objects_loaded = 90,
        completed = 100,
    };

    /// A pointer to the preinited game session
    session: *g.GameSession,
    progress: Progress,
    state: union(enum) { reading: Reader, file_closed } = .file_closed,
    file: g.Runtime.FileReader = undefined,
    level_depth: u8 = undefined,
    /// Helps to choose a ladder on which the player should appear on the loaded level.
    /// null means that player's position will be loaded together with game session.
    moving_direction: ?c.Ladder.Direction,

    pub fn loadSession(session: *g.GameSession) Loading {
        return .{ .session = session, .progress = .session_preinited, .moving_direction = null };
    }

    pub fn loadLevel(session: *g.GameSession, depth: u8, moving_direction: c.Ladder.Direction) Loading {
        return .{
            .session = session,
            .progress = .session_loaded,
            .level_depth = depth,
            .moving_direction = moving_direction,
        };
    }

    pub fn deinit(self: *Loading) void {
        switch (self.state) {
            .reading => |*reading| {
                reading.deinit();
                self.file.close();
            },
            .file_closed => {},
        }
    }

    // deinit should be called in case of any errors here
    pub fn tick(self: *Loading) !bool {
        log.debug("Continue loading: {s}", .{@tagName(self.progress)});
        try self.draw();
        switch (self.progress) {
            .session_preinited => {
                self.file = try self.session.runtime.fileReader(g.persistance.PATH_TO_SESSION_FILE);
                defer {
                    self.file.close();
                    self.state = .file_closed;
                }
                self.state = .{ .reading = Reader.init(&self.session.registry, self.file.reader()) };
                defer self.state.reading.deinit();

                try self.state.reading.beginObject();
                self.session.setSeed(try self.state.reading.readSeed());
                self.level_depth = try self.state.reading.readDepth();
                self.session.max_depth = try self.state.reading.readMaxDepth();
                self.session.player = try self.state.reading.readPlayer();
                try self.state.reading.endObject();

                self.session.level = g.Level.preInit(self.session.arena.allocator(), &self.session.registry);

                self.progress = .session_loaded;
            },
            .session_loaded => {
                var buf: [16]u8 = undefined;
                self.file =
                    try self.session.runtime.fileReader(try g.persistance.pathToLevelFile(&buf, self.level_depth));
                self.state = .{ .reading = Reader.init(&self.session.registry, self.file.reader()) };

                try self.state.reading.beginObject();
                const seed = try self.state.reading.readSeed();
                self.session.level.reset();
                try self.session.level.initWithEmptyDungeon(
                    self.session.player,
                    self.level_depth,
                    seed,
                );
                self.progress = .level_inited;
            },
            .level_inited => {
                try self.state.reading.readLevelEntities(&self.session.level);
                self.progress = .entities_loaded;
            },
            .entities_loaded => {
                try self.state.reading.readVisitedPlaces(&self.session.level);
                self.progress = .visited_places_loaded;
            },
            .visited_places_loaded => {
                try self.state.reading.readRememberedObjects(&self.session.level);
                self.progress = .remembered_objects_loaded;
            },
            .remembered_objects_loaded => {
                try self.state.reading.endObject();
                try self.session.level.completeInitialization(self.moving_direction);
                if (self.moving_direction == null)
                    try self.session.completeInitialization();

                self.state.reading.deinit();
                self.file.close();
                self.state = .file_closed;
                self.progress = .completed;
            },
            .completed => return false,
        }
        return true;
    }

    fn draw(self: Loading) !void {
        //       |
        // Loadin|g XXX%
        //       |
        if (self.progress == .session_preinited) {
            try self.session.render.clearDisplay();
            try self.session.render.drawTextWithAlign(
                7,
                "Loading",
                .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 - 6 },
                .normal,
                .left,
            );
        } else {
            var buf: [5]u8 = undefined;
            try self.session.render.drawTextWithAlign(
                buf.len,
                try std.fmt.bufPrint(&buf, " {d:3}%", .{@intFromEnum(self.progress)}),
                .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 + 1 },
                .normal,
                .left,
            );
        }
    }
};

const Saving = struct {
    const Writer = g.persistance.Writer(g.Runtime.FileWriter.Writer);

    const Progress = enum(u8) {
        inited = 0,
        session_saved = 20,
        level_seed_saved = 30,
        entities_saved = 70,
        visited_places_saved = 80,
        remembered_objects_saved = 95,
        completed = 100,
    };

    const NextProcess = union(enum) {
        load_level: struct { depth: u8, direction: c.Ladder.Direction },
        generate_level: struct { prng: std.Random.DefaultPrng, depth: u8, from_ladder: c.Ladder },
        go_to_welcome_screen,
    };

    session: *g.GameSession,
    progress: Progress = .inited,
    state: union(enum) { writing: Writer, file_closed } = .file_closed,
    file: g.Runtime.FileWriter = undefined,
    next_process: NextProcess,

    pub fn deinit(self: *Saving) void {
        switch (self.state) {
            .writing => |*writer| {
                writer.deinit();
                self.file.close();
            },
            .file_closed => {},
        }
    }

    // deinit should be called in case of any errors here
    pub fn tick(self: *Saving) !bool {
        log.debug("Continue saving: {s}", .{@tagName(self.progress)});
        try self.draw();
        switch (self.progress) {
            .inited => {
                self.file = try self.session.runtime.fileWriter(g.persistance.PATH_TO_SESSION_FILE);
                self.state = .{ .writing = Writer.init(&self.session.registry, self.file.writer()) };
                try self.state.writing.beginObject();
                try self.state.writing.writeSeed(self.session.seed);
                try self.state.writing.writeDepth(self.session.level.depth);
                try self.state.writing.writeMaxDepth(self.session.max_depth);
                try self.state.writing.writePlayer(self.session.player);
                try self.state.writing.endObject();
                self.state.writing.deinit();
                self.file.close();
                self.state = .file_closed;
                self.progress = .session_saved;
            },
            .session_saved => {
                var buf: [16]u8 = undefined;
                self.file =
                    try self.session.runtime.fileWriter(try g.persistance.pathToLevelFile(&buf, self.session.level.depth));
                self.state = .{ .writing = Writer.init(&self.session.registry, self.file.writer()) };

                try self.state.writing.beginObject();
                try self.state.writing.writeSeed(self.session.level.dungeon.seed);
                self.progress = .level_seed_saved;
            },
            .level_seed_saved => {
                try self.state.writing.writeLevelEntities(self.session.level.entities.items);
                self.progress = .entities_saved;
            },
            .entities_saved => {
                try self.state.writing.writeVisitedPlaces(self.session.level.visited_places);
                self.progress = .visited_places_saved;
            },
            .visited_places_saved => {
                try self.state.writing.writeRememberedObjects(self.session.level.remembered_objects);
                self.progress = .remembered_objects_saved;
            },
            .remembered_objects_saved => {
                try self.state.writing.endObject();
                for (self.session.level.entities.items) |entity| {
                    if (!entity.eql(self.session.player))
                        try self.session.registry.removeEntity(entity);
                }
                self.state.writing.deinit();
                self.file.close();
                self.state = .file_closed;
                self.progress = .completed;
            },
            .completed => return false,
        }
        return true;
    }

    fn draw(self: Saving) !void {
        //       |
        // Saving| XXX%
        //       |
        if (self.progress == .inited) {
            try self.session.render.clearDisplay();
            try self.session.render.drawTextWithAlign(
                6,
                "Saving",
                .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 - 6 },
                .normal,
                .left,
            );
        } else {
            var buf: [5]u8 = undefined;
            try self.session.render.drawTextWithAlign(
                buf.len,
                try std.fmt.bufPrint(&buf, " {d:3}%", .{@intFromEnum(self.progress)}),
                .{ .row = g.DISPLAY_ROWS / 2 - 1, .col = g.DISPLAY_COLS / 2 },
                .normal,
                .left,
            );
        }
    }
};
