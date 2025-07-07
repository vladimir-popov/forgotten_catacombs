const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.persistance);

pub const Writer = struct {
    registry: *const g.Registry,
    writer: std.json.WriteStream(g.Runtime.FileWriter.Writer, .checked_to_arbitrary_depth),

    pub fn init(alloc: std.mem.Allocator, registry: *const g.Registry, file_writer: g.Runtime.FileWriter) Writer {
        return .{
            .registry = registry,
            .writer = std.json.writeStreamArbitraryDepth(
                alloc,
                file_writer.writer(),
                .{ .emit_null_optional_fields = false },
            ),
        };
    }

    pub fn deinit(self: *Writer) void {
        self.writer.deinit();
    }

    // ==== The interface of any writer  =====

    pub fn beginObject(self: *Writer) !void {
        try self.writer.beginObject();
    }

    pub fn endObject(self: *Writer) !void {
        try self.writer.endObject();
    }

    pub fn beginCollection(self: *Writer) !void {
        try self.writer.beginArray();
    }

    pub fn endCollection(self: *Writer) !void {
        try self.writer.endArray();
    }

    fn writeStringKey(self: *Writer, name: []const u8) !void {
        try self.writer.objectField(name);
    }

    fn writeNumericKey(self: *Writer, key: anytype) !void {
        const type_info = @typeInfo(@TypeOf(key));
        var buf: [@divExact(type_info.int.bits, 8)]u8 = undefined;
        switch (type_info) {
            .int => try self.writeStringKey(try std.fmt.bufPrint(&buf, "{d}", .{key})),
            else => {
                log.err("Unsupported type for key {any}", .{@typeName(type_info)});
                return error.UnsupportedType;
            },
        }
    }

    fn writeValue(self: *Writer, value: anytype) !void {
        try self.writer.write(value);
    }
    // =====================================

    pub fn writeSeed(self: *Writer, seed: u64) !void {
        try self.writeStringKey("seed");
        try self.writeValue(seed);
    }

    pub fn writeLevelEntities(self: *Writer, entities: []g.Entity) !void {
        try self.writeStringKey("entities");
        try self.beginCollection();
        for (entities) |entity| {
            try self.writeEntity(entity);
        }
        try self.endCollection();
    }

    pub fn writeVisitedPlaces(self: *Writer, places: []std.DynamicBitSetUnmanaged) !void {
        try self.writeStringKey("visited_places");
        try self.beginCollection();
        for (places) |row| {
            var itr = row.iterator(.{});
            try self.beginCollection();
            while (itr.next()) |idx| {
                try self.writeValue(idx);
            }
            try self.endCollection();
        }
        try self.endCollection();
    }

    pub fn writeRememberedObjects(self: *Writer, objects: std.AutoHashMapUnmanaged(p.Point, g.Entity)) !void {
        try self.writeStringKey("remembered_objects");
        var itr = objects.iterator();
        try self.beginCollection();
        while (itr.next()) |kv| {
            try self.beginObject();
            try self.writeNumericKey(kv.value_ptr.id);
            try self.writeValue(kv.key_ptr.*);
            try self.endObject();
        }
        try self.endCollection();
    }

    fn writeEntity(self: *Writer, entity: g.Entity) !void {
        try self.beginObject();
        try self.writeNumericKey(entity.id);
        try self.writeComponents(try self.registry.entityToStruct(entity));
        try self.endObject();
    }

    fn writeComponents(self: *Writer, components: c.Components) !void {
        try self.beginObject();
        inline for (std.meta.fields(c.Components)) |field| {
            try self.writeStringKey(field.name);
            try self.write(@field(components, field.name));
        }
        try self.endObject();
    }

    fn writeEntitiesSet(self: *Writer, items: u.EntitiesSet) !void {
        try self.beginCollection();
        var itr = items.iterator();
        while (itr.next()) |entity| {
            try self.writeEntity(entity);
        }
        try self.endCollection();
    }

    fn write(self: *Writer, value: anytype) !void {
        const t = @TypeOf(value);
        if (t == g.Entity) {
            try self.writeEntity(@as(g.Entity, value));
        } else if (t == c.Components) {
            try self.writeComponents(@as(c.Components, value));
        } else if (t == c.Inventory or t == c.Pile) {
            try self.writeEntitiesSet(value.items);
        } else if (isDto(t)) {
            try self.writeValue(value);
        } else {
            log.err("Unsupported serialization for {any}. It should be DTO.", .{@typeName(@TypeOf(value))});
            return error.UnsupportedType;
        }
    }
};

pub const Reader = struct {
    /// This area is used to allocate every parsed value, and is used to manage memory consumption.
    /// It can be freed after any reading. This is why all read data have to be copied somewhere
    /// with more stable allocator.
    arena: *std.heap.ArenaAllocator,
    reader: std.json.Reader(4096, g.Runtime.FileReader.Reader),
    registry: *g.Registry,

    pub fn init(alloc: std.mem.Allocator, registry: *g.Registry, file_reader: g.Runtime.FileReader) !Reader {
        const arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);
        return .{
            .arena = arena,
            .reader = std.json.reader(arena.allocator(), file_reader.reader()),
            .registry = registry,
        };
    }

    pub fn deinit(self: *Reader) void {
        self.reader.deinit();
        const alloc = self.arena.child_allocator;
        self.arena.deinit();
        alloc.destroy(self.arena);
    }

    pub fn resetBuffer(self: *Reader) void {
        self.arena.reset(.retain_capacity);
    }

    // ==== The interface of any reader  =====

    pub fn beginObject(self: *Reader) !void {
        assertEql(try self.reader.next(), .object_begin);
    }

    pub fn endObject(self: *Reader) !void {
        assertEql(try self.reader.next(), .object_end);
    }

    pub fn isObjectEnd(self: *Reader) !bool {
        return try self.reader.peekNextTokenType() == .object_end;
    }

    pub fn beginCollection(self: *Reader) !void {
        assertEql(try self.reader.next(), .array_begin);
    }

    pub fn endCollection(self: *Reader) !void {
        assertEql(try self.reader.next(), .array_end);
    }

    pub fn isCollectionEnd(self: *Reader) !bool {
        return try self.reader.peekNextTokenType() == .array_end;
    }

    fn readStringKey(self: *Reader) ![]const u8 {
        return (try self.reader.nextAlloc(self.arena.allocator(), .alloc_if_needed)).string;
    }

    fn readNumericKey(self: *Reader, comptime N: type) !N {
        return try std.fmt.parseInt(N, try self.readStringKey(), 10);
    }

    fn readNumber(self: *Reader, comptime T: type) !T {
        return try std.fmt.parseInt(T, (try self.reader.next()).number, 10);
    }

    fn readValue(self: *Reader, comptime T: type) !T {
        const value = try std.json.Value.jsonParse(self.arena.allocator(), self.reader, .{});
        try std.json.parseFromValueLeaky(T, self.arena.allocator(), value);
    }
    // =====================================

    pub fn readSeed(self: *Reader) !u64 {
        assertEql(try self.readStringKey(), "seed");
        return try self.readNumber(u64);
    }

    pub fn readLevelEntities(self: *Reader, level: *g.Level) !void {
        assertEql(try self.readStringKey(), "entities");
        const alloc = level.arena.allocator();
        try self.beginCollection();
        while (try self.isCollectionEnd()) {
            level.entities.append(alloc, try self.readEntity(level.registry));
        }
        try self.endCollection();
    }

    pub fn readVisitedPlaces(self: *Reader, level: *g.Level) ![]std.DynamicBitSetUnmanaged {
        assertEql(try self.readStringKey(), "visited_places");
        try self.beginCollection();
        for (0..level.dungeon.rows) |i| {
            try self.beginCollection();
            while (try self.isCollectionEnd())
                level.visited_places[i].set(try self.readNumber(usize));
            try self.endCollection();
        }
        try self.endCollection();
    }

    pub fn readRememberedObjects(self: *Reader, level: *g.Level) !void {
        assertEql(try self.readStringKey(), "remembered_objects");
        try self.beginCollection();
        const alloc = level.arena.allocator();
        while (!try self.isCollectionEnd()) {
            try self.beginObject();
            const entity = g.Entity{ .id = try self.readNumericKey(g.Entity.IdType).? };
            const place = try self.readValue(p.Point);
            level.remembered_objects.put(alloc, place, entity);
            try self.endObject();
        }
        try self.endCollection();
    }

    fn readEntity(self: *Reader, registry: *g.Registry) !g.Entity {
        try self.beginObject();
        const entity = g.Entity{ .id = try self.readNumericKey(g.Entity.IdType) };
        try self.readComponents(entity, registry);
        try self.endObject();
        return entity;
    }

    fn readComponents(self: *Reader, entity: g.Entity, registry: *g.Registry) !void {
        try self.beginObject();
        while (!try self.isObjectEnd()) {
            const key = (try self.readStringKey());
            const typeTag: g.Registry.TypeTag = std.meta.stringToEnum(g.Registry.TypeTag, key).?;
            const C = @FieldType(c.Components, @tagName(typeTag));
            try self.readComponent(C, entity, registry);
        }
        try self.endObject();
    }

    fn readComponent(self: *Reader, comptime C: type, entity: g.Entity, registry: *g.Registry) !void {
        const component: C = if (C == c.Inventory or C == c.Pile)
            C{ .items = self.readEntitiesSet(registry) }
        else if (isDto(C))
            try self.readValue(C)
        else {
            log.err("Unsupported deserialization for {any}. It should be DTO.", .{@typeName(C)});
            return error.UnsupportedType;
        };
        try registry.set(entity, C, component);
    }

    fn readEntitiesSet(self: *Reader, registry: *g.Registry) !u.EntitiesSet {
        var set = u.EntitiesSet.empty(registry.alloc);
        try self.beginCollection();
        while (!try self.isCollectionEnd()) {
            try set.add(try self.readEntity(registry));
        }
        try self.endCollection();
        return set;
    }
};

fn isDto(t: type) bool {
    switch (@typeInfo(t)) {
        .null, .bool, .int, .float, .comptime_int, .comptime_float, .@"enum", .enum_literal => return true,
        .optional => |op| return isDto(op.child),
        .array => |arr| return isDto(arr.child),
        .@"struct" => |s| {
            inline for (s.fields) |field| {
                if (!isDto(field.type)) return false;
            }
            return true;
        },
        .@"union" => |un| {
            if (un.tag_type == null) return false;
            for (un.fields) |field| {
                if (!isDto(field.type)) return false;
            }
            return true;
        },
        else => return false,
    }
}

fn assertEql(actual: anytype, expected: anytype) void {
    switch (@import("builtin").mode) {
        .Debug, .ReleaseSafe => switch (@typeInfo(@TypeOf(expected))) {
            .enum_literal => if (actual != expected)
                std.debug.panic("Expected {any}, but was {any}", .{ expected, actual }),
            else => if (!std.mem.eql(u8, actual, expected))
                std.debug.panic("Expected {s}, but was {s}", .{ expected, actual }),
        },
        else => {},
    }
}
