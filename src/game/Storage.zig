const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.storage);

const Percent = u8;

const JsonTag = enum {
    depth,
    dungeon_seed,
    entity,
    entities,
    place,
    remembered_objects,
    visited_places,

    pub fn writeAsField(self: JsonTag, jws: anytype) !void {
        try jws.objectField(@tagName(self));
    }

    pub fn readFromField(json: anytype) !JsonTag {
        const next = try json.next();
        if (next == .string) {
            return std.meta.stringToEnum(JsonTag, next.string) orelse error.WrongTag;
        } else {
            log.err("Expected a string with tag, but had {any}", .{next});
            return error.WrongTag;
        }
    }
};

const Self = @This();

session: *g.GameSession,

/// Reads json from the reader, deserializes and initializes the level.
pub fn loadLevel(
    self: *Self,
    level: *g.Level,
    reader: g.Runtime.FileReader,
    direction: c.Ladder.Direction,
    progress: Percent,
) !Percent {
    _ = progress;

    level.preinit(self.session);
    const alloc = level.arena.allocator();

    var json = std.json.reader(level.arena.allocator(), reader.reader());
    defer json.deinit();

    assertEql(try json.next(), .object_begin);

    // Read the depth and dungeon seed to initialize the level.
    // They have to be the first two fields in the current json object
    var depth: ?u8 = null;
    var dungeon_seed: ?u64 = null;
    var next_tag: JsonTag = undefined;
    while (true) {
        next_tag = try JsonTag.readFromField(&json);
        switch (next_tag) {
            .depth => depth = try std.fmt.parseInt(u8, (try json.next()).number, 10),
            .dungeon_seed => dungeon_seed = try std.fmt.parseInt(u64, (try json.next()).number, 10),
            else => break,
        }
    }
    const dungeon = (try level.generateDungeon(depth.?, dungeon_seed.?)) orelse {
        log.err("A dungeon was not generate from the saved seed {d}", .{dungeon_seed.?});
        return error.BrokenSeed;
    };
    try level.setupDungeon(depth.?, dungeon);

    // Read other fields and set them to the already initialized level
    loop: while (true) {
        switch (next_tag) {
            .entities => {
                assertEql(try json.next(), .object_begin);
                while (try json.peekNextTokenType() != .object_end) {
                    const entity = try self.loadEntity(alloc, &json);
                    try level.entities.append(alloc, entity);
                }
                std.debug.assert(try json.next() == .object_end);
            },
            .visited_places => {
                assertEql(try json.next(), .array_begin);
                for (0..level.visited_places.len) |i| {
                    var value = try std.json.Value.jsonParse(alloc, &json, .{ .max_value_len = 1024 });
                    defer value.array.deinit();
                    for (value.array.items) |idx| {
                        level.visited_places[i].set(@intCast(idx.integer));
                    }
                }
                assertEql(try json.next(), .array_end);
            },
            .remembered_objects => {
                assertEql(try json.next(), .array_begin);
                while (try json.peekNextTokenType() != .array_end) {
                    var value = try std.json.Value.jsonParse(alloc, &json, .{ .max_value_len = 1024 });
                    defer value.object.deinit();
                    const entity = g.Entity{ .id = @intCast(value.object.get("entity").?.integer) };
                    const place = value.object.get("place").?;
                    try level.remembered_objects.put(alloc, try p.Point.jsonParseFromValue(alloc, place, .{}), entity);
                }
                assertEql(try json.next(), .array_end);
            },
            else => break :loop,
        }
        switch (try json.peekNextTokenType()) {
            .string => {
                next_tag = try JsonTag.readFromField(&json);
            },
            .object_end => {
                _ = try json.next();
                break :loop;
            },
            else => |unexpected| {
                log.err("Unexpected token `{any}`", .{unexpected});
                return error.UnexpectedToken;
            },
        }
    }
    assertEql(try json.next(), .end_of_document);

    try level.completeInitialization(direction);
    return 100;
}

pub fn saveLevel(
    self: *Self,
    alloc: std.mem.Allocator,
    level: g.Level,
    writer: g.Runtime.FileWriter,
    progress: Percent,
) !Percent {
    _ = progress;

    var jws = std.json.writeStreamArbitraryDepth(alloc, writer.writer(), .{ .emit_null_optional_fields = false });
    defer jws.deinit();

    try jws.beginObject();
    try JsonTag.depth.writeAsField(&jws);
    try jws.write(level.depth);
    try JsonTag.dungeon_seed.writeAsField(&jws);
    try jws.write(level.dungeon.seed);
    try JsonTag.entities.writeAsField(&jws);
    try jws.beginObject();
    for (level.entities.items) |entity| {
        try self.saveEntity(entity, &jws);
    }
    try jws.endObject();
    try JsonTag.visited_places.writeAsField(&jws);
    try jws.beginArray();
    for (level.visited_places) |visited_row| {
        try jws.beginArray();
        var itr = visited_row.iterator(.{});
        while (itr.next()) |idx| {
            try jws.write(idx);
        }
        try jws.endArray();
    }
    try jws.endArray();

    try JsonTag.remembered_objects.writeAsField(&jws);
    var kvs = level.remembered_objects.iterator();
    try jws.beginArray();
    while (kvs.next()) |kv| {
        try jws.beginObject();
        try JsonTag.place.writeAsField(&jws);
        try jws.write(kv.key_ptr.*);
        try JsonTag.entity.writeAsField(&jws);
        try jws.write(kv.value_ptr.id);
        try jws.endObject();
    }
    try jws.endArray();
    try jws.endObject();

    return 100;
}

/// Writes an entity as a pair `"id" : { components }`
fn saveEntity(self: Self, entity: g.Entity, jws: anytype) !void {
    var buf: [5]u8 = undefined;
    try jws.objectField(try std.fmt.bufPrint(&buf, "{d}", .{entity.id}));
    try jws.write(try self.session.entities.entityToStruct(entity));
}

/// Reads a pair `"<number>" : <json object>` as entity id and its components.
fn loadEntity(self: *Self, alloc: std.mem.Allocator, json: anytype) !g.Entity {
    const entity = g.Entity.parse((try json.next()).string).?;
    var value = try std.json.Value.jsonParse(alloc, json, .{ .max_value_len = 1024 });
    defer value.object.deinit();
    const parsed_components = try std.json.parseFromValue(c.Components, alloc, value, .{});
    defer parsed_components.deinit();
    try self.session.entities.copyComponentsToEntity(entity, parsed_components.value);
    return entity;
}

fn assertEql(actual: anytype, expected: anytype) void {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => if (expected != actual) {
            std.debug.panic("Expected {any}, but was {any}", .{ expected, actual });
        },
        else => {},
    }
}
