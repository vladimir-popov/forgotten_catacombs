const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const p = g.primitives;

const log = std.log.scoped(.saving);

const Percent = u8;

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

const Self = @This();

session: *g.GameSession,
progress: Progress = .inited,
state: union(enum) { writing: Writer, file_closed } = .file_closed,
file: g.Runtime.FileWriter = undefined,

pub fn saveSession(session: *g.GameSession) !Self {
    return .{ .session = session };
}

pub fn deinit(self: *Self) void {
    switch (self.state) {
        .writing => |*writer| {
            writer.deinit();
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
            _ = self.session.level.arena.deinit();
            self.state.writing.deinit();
            self.file.close();
            self.state = .file_closed;
            self.progress = .completed;
        },
        .completed => unreachable,
    }
    return true;
}

fn draw(self: Self) !void {
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
