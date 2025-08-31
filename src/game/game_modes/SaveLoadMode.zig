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
                log.err(
                    "Error on loading level on depth {d}. Progress before error: '{t}'",
                    .{ loading.level_depth, loading.progress },
                );
                return err;
            };
            if (!is_continue) {
                // the einit will be invoked for the whole SaveLoadMode here:
                try loading.session.playerMovedToLevel();
            }
        },
        .generating => |*generating| {
            try generating.draw();
            const seed = generating.prng.next();
            log.debug(
                "Start {d} attempt of generating a level {s} on depth {d} from the ladder {any}. Seed is {d}",
                .{
                    generating.attempt,
                    @tagName(generating.from_ladder.direction),
                    generating.depth,
                    generating.from_ladder,
                    seed,
                },
            );
            generating.session.level.reset();
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
    attempt: u8 = 1,

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
        if (self.attempt == 1) {
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
    const Progress = enum(u8) {
        load_session = 0,
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
    state: union(enum) { reading: g.persistance.Reader, file_closed } = .file_closed,
    file: g.Runtime.OpaqueFile = undefined,
    io_buffer: [128]u8 = undefined,
    level_depth: u8 = undefined,
    /// Helps to choose a ladder on which the player should appear on the loaded level.
    /// null means that player's position will be loaded together with game session.
    moving_direction: ?c.Ladder.Direction,

    pub fn loadSession(session: *g.GameSession) Loading {
        return .{ .session = session, .progress = .load_session, .moving_direction = null };
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
                self.session.runtime.closeFile(self.file);
            },
            .file_closed => {},
        }
    }

    pub fn tick(self: *Loading) !bool {
        log.debug("Continue loading: {t}", .{self.progress});
        try self.draw();
        switch (self.progress) {
            .load_session => {
                self.file = try self.session.runtime.openFile(
                    g.persistance.PATH_TO_SESSION_FILE,
                    .read,
                    &self.io_buffer,
                );
                defer {
                    self.session.runtime.closeFile(self.file);
                    self.state = .file_closed;
                }
                self.state = .{ .reading = .init(&self.session.registry, self.session.runtime.readFile(self.file)) };
                defer self.state.reading.deinit();

                try self.state.reading.beginObject();
                _ = try self.state.reading.readKey("seed");
                self.session.setSeed(try self.state.reading.read(u64));
                log.debug("A seed is {d}", .{self.session.seed});

                _ = try self.state.reading.readKey("next_entity");
                self.session.registry.next_entity = .{ .id = try self.state.reading.read(g.Entity.IdType) };

                _ = try self.state.reading.readKey("depth");
                self.level_depth = try self.state.reading.read(u8);

                _ = try self.state.reading.readKey("max_depth");
                self.session.max_depth = try self.state.reading.read(u8);

                _ = try self.state.reading.readKey("player");
                self.session.player = try self.state.reading.readEntity();
                try self.state.reading.endObject();
                log.debug("A game session was loaded.", .{});

                self.session.level = g.Level.preInit(self.session.arena.allocator(), &self.session.registry);
                log.debug("A level was preinited.", .{});

                self.progress = .session_loaded;
            },
            .session_loaded => {
                var path_buf: [16]u8 = undefined;
                self.file =
                    try self.session.runtime.openFile(
                        try g.persistance.pathToLevelFile(&path_buf, self.level_depth),
                        .read,
                        &self.io_buffer,
                    );
                self.state = .{ .reading = .init(&self.session.registry, self.session.runtime.readFile(self.file)) };

                try self.state.reading.beginObject();
                _ = try self.state.reading.readKey("seed");
                const seed = try self.state.reading.read(u64);

                self.session.level.reset();
                try self.session.level.initWithEmptyDungeon(
                    self.session.player,
                    self.level_depth,
                    seed,
                );
                self.progress = .level_inited;
            },
            .level_inited => {
                _ = try self.state.reading.readKey("entities");
                const alloc = self.session.level.arena.allocator();
                try self.state.reading.beginCollection();
                while (!try self.state.reading.isCollectionEnd()) {
                    try self.session.level.entities_on_level.append(alloc, try self.state.reading.readEntity());
                }
                try self.state.reading.endCollection();
                self.session.level.bindDoorsWithDoorways();
                self.progress = .entities_loaded;
            },
            .entities_loaded => {
                _ = try self.state.reading.readKey("visited_places");
                try self.state.reading.beginCollection();
                for (0..self.session.level.dungeon.rows) |i| {
                    try self.state.reading.beginCollection();
                    while (!try self.state.reading.isCollectionEnd())
                        self.session.level.visited_places[i].set(try self.state.reading.read(usize));
                    try self.state.reading.endCollection();
                }
                try self.state.reading.endCollection();
                self.progress = .visited_places_loaded;
            },
            .visited_places_loaded => {
                var buf: [128]u8 = undefined;
                _ = try self.state.reading.readKey("remembered_objects");
                try self.state.reading.beginCollection();
                const alloc = self.session.level.arena.allocator();
                while (!try self.state.reading.isCollectionEnd()) {
                    try self.state.reading.beginObject();
                    const entity = g.Entity{ .id = try self.state.reading.readKeyAsNumber(g.Entity.IdType, &buf) };
                    const place = try self.state.reading.read(p.Point);
                    try self.session.level.remembered_objects.put(alloc, place, entity);
                    try self.state.reading.endObject();
                }
                try self.state.reading.endCollection();
                self.progress = .remembered_objects_loaded;
            },
            .remembered_objects_loaded => {
                try self.state.reading.endObject();
                try self.session.level.completeInitialization(self.moving_direction);
                if (self.moving_direction == null)
                    try self.session.completeInitialization();

                self.state.reading.deinit();
                self.session.runtime.closeFile(self.file);
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
        if (self.progress == .load_session or self.progress == .session_loaded) {
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
    state: union(enum) { writing: g.persistance.Writer, file_closed } = .file_closed,
    file: g.Runtime.OpaqueFile = undefined,
    io_buffer: [128]u8 = undefined,
    next_process: NextProcess,

    pub fn deinit(self: *Saving) void {
        switch (self.state) {
            .writing => {
                self.session.runtime.closeFile(self.file);
            },
            .file_closed => {},
        }
    }

    pub fn tick(self: *Saving) !bool {
        log.debug("Continue saving: {s}", .{@tagName(self.progress)});
        try self.draw();
        switch (self.progress) {
            .inited => {
                self.file = try self.session.runtime.openFile(
                    g.persistance.PATH_TO_SESSION_FILE,
                    .write,
                    &self.io_buffer,
                );
                self.state = .{
                    .writing = .init(&self.session.registry, self.session.runtime.writeToFile(self.file)),
                };
                try self.state.writing.beginObject();
                try self.state.writing.writeStringKey("seed");
                try self.state.writing.write(self.session.seed);
                try self.state.writing.writeStringKey("next_entity");
                try self.state.writing.write(self.session.registry.next_entity.id);
                try self.state.writing.writeStringKey("depth");
                try self.state.writing.write(self.session.level.depth);
                try self.state.writing.writeStringKey("max_depth");
                try self.state.writing.write(self.session.max_depth);
                try self.state.writing.writeStringKey("player");
                try self.state.writing.writeEntity(self.session.player);
                try self.state.writing.endObject();
                self.session.runtime.closeFile(self.file);
                self.state = .file_closed;
                self.progress = .session_saved;
            },
            .session_saved => {
                var buf: [16]u8 = undefined;
                self.file = try self.session.runtime.openFile(
                    try g.persistance.pathToLevelFile(&buf, self.session.level.depth),
                    .write,
                    &self.io_buffer,
                );
                self.state = .{
                    .writing = .init(&self.session.registry, self.session.runtime.writeToFile(self.file)),
                };

                try self.state.writing.beginObject();
                try self.state.writing.writeStringKey("seed");
                try self.state.writing.write(self.session.level.dungeon.seed);
                self.progress = .level_seed_saved;
            },
            .level_seed_saved => {
                try self.state.writing.writeStringKey("entities");
                try self.state.writing.beginCollection();
                for (self.session.level.entities_on_level.items) |entity| {
                    try self.state.writing.writeEntity(entity);
                }
                try self.state.writing.endCollection();
                self.progress = .entities_saved;
            },
            .entities_saved => {
                try self.state.writing.writeStringKey("visited_places");
                try self.state.writing.beginCollection();
                for (self.session.level.visited_places) |row| {
                    var itr = row.iterator(.{});
                    try self.state.writing.beginCollection();
                    while (itr.next()) |idx| {
                        try self.state.writing.write(idx);
                    }
                    try self.state.writing.endCollection();
                }
                try self.state.writing.endCollection();
                self.progress = .visited_places_saved;
            },
            .visited_places_saved => {
                try self.state.writing.writeStringKey("remembered_objects");
                var itr = self.session.level.remembered_objects.iterator();
                try self.state.writing.beginCollection();
                while (itr.next()) |kv| {
                    try self.state.writing.beginObject();
                    try self.state.writing.writeNumericKey(kv.value_ptr.id);
                    try self.state.writing.write(kv.key_ptr.*);
                    try self.state.writing.endObject();
                }
                try self.state.writing.endCollection();
                self.progress = .remembered_objects_saved;
            },
            .remembered_objects_saved => {
                try self.state.writing.endObject();
                for (self.session.level.entities_on_level.items) |entity| {
                    if (!entity.eql(self.session.player))
                        try self.session.registry.removeEntity(entity);
                }
                self.session.runtime.closeFile(self.file);
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
