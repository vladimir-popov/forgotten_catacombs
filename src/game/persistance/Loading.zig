const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.saving);

const Percent = u8;

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

const Self = @This();

session: *g.GameSession,
progress: Progress,
state: union(enum) { reading: Reader, file_closed } = .file_closed,
file: g.Runtime.FileReader = undefined,
level_depth: u8 = undefined,
/// Helps to choose a ladder on which the player should appear on the loaded level.
/// null means that player's position will be loaded together with game session.
moving_direction: ?c.Ladder.Direction,

pub fn loadSession(session: *g.GameSession) Self {
    return .{ .session = session, .progress = .session_preinited, .moving_direction = null };
}

pub fn loadLevel(session: *g.GameSession, depth: u8, moving_direction: c.Ladder.Direction) Self {
    return .{
        .session = session,
        .progress = .session_loaded,
        .level_depth = depth,
        .moving_direction = moving_direction,
    };
}

pub fn deinit(self: *Self) void {
    switch (self.state) {
        .reading => |*reading| {
            reading.deinit();
            self.file.close();
        },
        .file_closed => {},
    }
}

// deinit should be called in case of any errors here
pub fn tick(self: *Self) !bool {
    if (self.progress == .completed) return false;
    try self.draw();
    switch (self.progress) {
        .session_preinited => {
            self.file = try self.session.runtime.fileReader(g.persistance.PATH_TO_SESSION_FILE);
            self.state = .{ .reading = Reader.init(&self.session.registry, self.file.reader()) };
            try self.state.reading.beginObject();
            self.session.prng.seed(try self.state.reading.readSeed());
            self.level_depth = try self.state.reading.readDepth();
            self.session.max_depth = try self.state.reading.readMaxDepth();
            self.session.player = try self.state.reading.readPlayer();
            try self.state.reading.endObject();
            self.state.reading.deinit();
            self.file.close();
            self.state = .file_closed;
            self.progress = .session_loaded;
        },
        .session_loaded => {
            var buf: [16]u8 = undefined;
            self.file =
                try self.session.runtime.fileReader(try g.persistance.pathToLevelFile(&buf, self.level_depth));
            self.state = .{ .reading = Reader.init(&self.session.registry, self.file.reader()) };
            try self.state.reading.beginObject();
            const seed = try self.state.reading.readSeed();
            self.session.level = try g.Level.initEmpty(
                self.session.arena.allocator(),
                &self.session.registry,
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
            try self.session.completeInitialization();
            // the game sessions is switched to the `play` mde here,
            // and self.deinit will be invoked inside this function:
            try self.session.playerMovedToLevel();
            self.progress = .completed;
        },
        .completed => unreachable,
    }
    return true;
}

fn draw(self: Self) !void {
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
