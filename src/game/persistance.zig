//! The persistence layer currently implemented with Json format.
//! Note, that this implementation is order sensitive. It means that fields of every persisted
//! structures must follow the same order on reading in which they were written.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.persistence);

pub const PATH_TO_SESSION_FILE = "session.json";

pub fn pathToLevelFile(buf: []u8, depth: u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "level_{d}.json", .{depth});
}

pub fn Writer(comptime Underlying: type) type {
    return struct {
        const Self = @This();

        pub const Error = anyerror;

        // used to get components of entities inside containers such as pile or inventory
        registry: *const g.Registry,
        writer: std.json.WriteStream(Underlying, .{ .checked_to_fixed_depth = 256 }),

        pub fn init(registry: *const g.Registry, writer: Underlying) Self {
            return .{
                .registry = registry,
                .writer = std.json.writeStream(
                    writer,
                    .{ .emit_null_optional_fields = false },
                ),
            };
        }

        pub fn deinit(self: *Self) void {
            self.writer.deinit();
        }

        pub fn beginObject(self: *Self) Error!void {
            try self.writer.beginObject();
        }

        pub fn endObject(self: *Self) Error!void {
            try self.writer.endObject();
        }

        pub fn writeSeed(self: *Self, seed: u64) Error!void {
            try self.writeStringKey("seed");
            try self.writeValue(seed);
        }

        pub fn writeDepth(self: *Self, depth: u8) Error!void {
            try self.writeStringKey("depth");
            try self.writeValue(depth);
        }

        pub fn writeMaxDepth(self: *Self, depth: u8) Error!void {
            try self.writeStringKey("max_depth");
            try self.writeValue(depth);
        }

        pub fn writeLevelEntities(self: *Self, entities: []g.Entity) Error!void {
            try self.writeStringKey("entities");
            try self.beginCollection();
            for (entities) |entity| {
                try self.writeEntity(entity);
            }
            try self.endCollection();
        }

        pub fn writeVisitedPlaces(self: *Self, places: []std.DynamicBitSetUnmanaged) Error!void {
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

        pub fn writeRememberedObjects(self: *Self, objects: std.AutoHashMapUnmanaged(p.Point, g.Entity)) Error!void {
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

        pub fn writePlayer(self: *Self, entity: g.Entity) Error!void {
            try self.writeStringKey("player");
            try self.writeEntity(entity);
        }

        fn writeEntity(self: *Self, entity: g.Entity) Error!void {
            try self.beginObject();
            try self.writeNumericKey(entity.id);
            try self.write(try self.registry.entityToStruct(entity));
            try self.endObject();
        }

        fn writeEntitiesSet(self: *Self, items: u.EntitiesSet) Error!void {
            try self.beginCollection();
            var itr = items.iterator();
            while (itr.next()) |entity| {
                try self.writeEntity(entity.*);
            }
            try self.endCollection();
        }

        fn write(self: *Self, value: anytype) Error!void {
            const T = @TypeOf(value);
            if (T == u.EntitiesSet) {
                try self.writeEntitiesSet(@as(u.EntitiesSet, value));
                return;
            }
            switch (@typeInfo(T)) {
                .bool, .int, .float, .comptime_int, .comptime_float, .@"enum", .enum_literal => {
                    try self.writeValue(value);
                },
                .optional => if (value == null) {
                    log.err("null is not supported value.", .{});
                    return error.UnsupportedType;
                } else try self.write(value.?),
                .array => |arr| {
                    try self.beginCollection();
                    for (0..arr.len) |i| {
                        try self.write(value[i]);
                    }
                    try self.endCollection();
                },
                .pointer => |ptr| if (ptr.size == .slice) { // a single pointer is not supported
                    try self.beginCollection();
                    for (value) |v| {
                        try self.write(v);
                    }
                    try self.endCollection();
                },
                .@"struct" => |s| {
                    try self.beginObject();
                    inline for (s.fields) |field| {
                        const f_value = @field(value, field.name);
                        if (@typeInfo(field.type) != .optional or f_value != null) {
                            try self.writeStringKey(field.name);
                            self.write(f_value) catch |err| {
                                log.err("Error on writing {s}.{s}: {any}", .{ @typeName(T), field.name, err });
                                return err;
                            };
                        }
                    }
                    try self.endObject();
                },
                .@"union" => |un| {
                    // not tagged unions are not supported
                    if (un.tag_type) |tt| {
                        try self.beginObject();
                        inline for (un.fields) |u_field| {
                            if (value == @field(tt, u_field.name)) {
                                try self.writeStringKey(u_field.name);
                                if (u_field.type == void) {
                                    // void value is {}
                                    try self.beginObject();
                                    try self.endObject();
                                } else {
                                    try self.write(@field(value, u_field.name));
                                }
                                break;
                            }
                        }
                        try self.endObject();
                    }
                },
                else => {
                    log.err("Unsupported type for serialization: {s}.", .{@typeName(T)});
                    return error.UnsupportedType;
                },
            }
        }

        fn beginCollection(self: *Self) Error!void {
            try self.writer.beginArray();
        }

        fn endCollection(self: *Self) Error!void {
            try self.writer.endArray();
        }

        fn writeStringKey(self: *Self, name: []const u8) Error!void {
            try self.writer.objectField(name);
        }

        fn writeNumericKey(self: *Self, key: anytype) Error!void {
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

        fn writeValue(self: *Self, value: anytype) Error!void {
            try self.writer.write(value);
        }
    };
}

pub fn Reader(comptime Underlying: type) type {
    return struct {
        const Self = @This();
        pub const Error = anyerror;

        registry: *g.Registry,
        reader: std.json.Reader(512, Underlying),
        // a buffer for object keys. helps to avoid allocations
        string_buffer: [128]u8 = undefined,

        pub fn init(registry: *g.Registry, reader: Underlying) Self {
            return .{
                .registry = registry,
                .reader = std.json.Reader(512, Underlying).init(registry.allocator(), reader),
            };
        }

        pub fn deinit(self: *Self) void {
            self.reader.deinit();
        }

        pub fn beginObject(self: *Self) Error!void {
            try assertEql(self.reader.next(), .object_begin);
        }

        pub fn endObject(self: *Self) Error!void {
            try assertEql(self.reader.next(), .object_end);
        }

        pub fn readSeed(self: *Self) Error!u64 {
            try assertEql(self.readStringKey(), "seed");
            return try self.readNumber(u64);
        }

        pub fn readDepth(self: *Self) Error!u8 {
            try assertEql(self.readStringKey(), "depth");
            return try self.readNumber(u8);
        }

        pub fn readMaxDepth(self: *Self) Error!u8 {
            try assertEql(self.readStringKey(), "max_depth");
            return try self.readNumber(u8);
        }

        pub fn readLevelEntities(self: *Self, level: *g.Level) Error!void {
            try assertEql(self.readStringKey(), "entities");
            const alloc = level.arena.allocator();
            try self.beginCollection();
            while (!try self.isCollectionEnd()) {
                try level.entities.append(alloc, try self.readEntity());
            }
            try self.endCollection();
        }

        pub fn readVisitedPlaces(self: *Self, level: *g.Level) Error!void {
            try assertEql(self.readStringKey(), "visited_places");
            try self.beginCollection();
            for (0..level.dungeon.rows) |i| {
                try self.beginCollection();
                while (!try self.isCollectionEnd())
                    level.visited_places[i].set(try self.readNumber(usize));
                try self.endCollection();
            }
            try self.endCollection();
        }

        pub fn readRememberedObjects(self: *Self, level: *g.Level) Error!void {
            try assertEql(self.readStringKey(), "remembered_objects");
            try self.beginCollection();
            const alloc = level.arena.allocator();
            while (!try self.isCollectionEnd()) {
                try self.beginObject();
                const entity = g.Entity{ .id = try self.readNumericKey(g.Entity.IdType) };
                const place = try self.readValue(p.Point);
                try level.remembered_objects.put(alloc, place, entity);
                try self.endObject();
            }
            try self.endCollection();
        }

        pub fn readPlayer(self: *Self) anyerror!g.Entity {
            try assertEql(self.readStringKey(), "player");
            return try self.readEntity();
        }

        fn readEntity(self: *Self) anyerror!g.Entity {
            try self.beginObject();
            const entity = g.Entity{ .id = try self.readNumericKey(g.Entity.IdType) };
            const components = self.read(c.Components) catch |err| {
                log.err("Error on reading components of the entity {d}", .{entity.id});
                return err;
            };
            try self.registry.setComponentsToEntity(entity, components);
            try self.endObject();
            return entity;
        }

        fn readEntitiesSet(self: *Self) Error!u.EntitiesSet {
            const set = try u.EntitiesSet.init(self.registry.allocator());
            try self.beginCollection();
            while (!try self.isCollectionEnd()) {
                try set.add(try self.readEntity());
            }
            try self.endCollection();
            return set;
        }

        // registry is used in case of EntitiesSet, to store the components during deserialization.
        fn read(self: *Self, comptime T: type) Error!T {
            if (T == u.EntitiesSet) {
                return @as(T, try self.readEntitiesSet());
            }
            switch (@typeInfo(T)) {
                .void => {
                    try self.beginObject();
                    try self.endObject();
                    return {};
                },
                .bool, .int, .comptime_int, .float, .comptime_float, .@"enum", .enum_literal => {
                    return try self.readValue(T);
                },
                .optional => |op| {
                    return try self.read(op.child);
                },
                .array => |arr| {
                    var buf: [arr.len]arr.child = undefined;
                    try self.beginCollection();
                    for (0..arr.len) |i| {
                        buf[i] = try self.read(arr.child);
                    }
                    try self.endCollection();
                    return buf;
                },
                .pointer => |ptr| if (ptr.size == .slice) {
                    const buf: std.ArrayListUnmanaged(ptr.child) = .empty;
                    errdefer buf.deinit(self.registry.alloc);

                    try self.beginCollection();
                    while (!try self.isCollectionEnd()) {
                        const item = buf.addOne(self.registry.alloc);
                        item.* = try self.read(ptr.child);
                    }
                    try self.endCollection();
                    return buf.toOwnedSlice();
                },
                .@"struct" => |s| {
                    try self.beginObject();
                    var result: T = undefined;
                    var key: ?[]const u8 = null;
                    inline for (s.fields) |field| {
                        if (key == null) {
                            key = try self.readStringKey();
                        }
                        if (std.mem.eql(u8, field.name, key.?)) {
                            @field(&result, field.name) = self.read(field.type) catch |err| {
                                log.err("Error on reading value of the field {s}", .{field.name});
                                return err;
                            };
                            key = null;
                        } else if (@typeInfo(field.type) == .optional) {
                            @field(&result, field.name) = null;
                        } else {
                            log.err(
                                "Error on reading {s}. Expected a key for the field {s}, but was read {s}",
                                .{ @typeName(T), field.name, key.? },
                            );
                            return error.WrongInput;
                        }
                    }
                    try self.endObject();
                    return result;
                },
                .@"union" => |un| {
                    try self.beginObject();
                    const key = try self.readStringKey();
                    inline for (un.fields) |u_field| {
                        if (std.mem.eql(u8, u_field.name, key)) {
                            return @unionInit(T, u_field.name, try self.read(u_field.type));
                        }
                    }
                    try self.endObject();
                },
                else => {},
            }
            log.err("Unsupported type for desrialization {s}", .{@typeName(T)});
            return error.UnsupportedType;
        }

        fn isObjectEnd(self: *Self) Error!bool {
            return try self.reader.peekNextTokenType() == .object_end;
        }

        fn beginCollection(self: *Self) Error!void {
            try assertEql(self.reader.next(), .array_begin);
        }

        fn endCollection(self: *Self) Error!void {
            try assertEql(self.reader.next(), .array_end);
        }

        fn isCollectionEnd(self: *Self) Error!bool {
            return try self.reader.peekNextTokenType() == .array_end;
        }

        fn readStringKey(self: *Self) Error![]const u8 {
            return try self.readSymbols();
        }

        fn readNumericKey(self: *Self, comptime N: type) Error!N {
            return try std.fmt.parseInt(N, try self.readStringKey(), 10);
        }

        fn readNumber(self: *Self, comptime T: type) Error!T {
            return try std.fmt.parseInt(T, try self.readSymbols(), 10);
        }

        fn readValue(self: *Self, comptime T: type) Error!T {
            switch (@typeInfo(T)) {
                .bool => {
                    const next = try self.reader.next();
                    return if (next == .true) true else if (next == .false) false else {
                        log.err("Wrong input. Expected bool, but was {any}", .{next});
                        return error.WrongInput;
                    };
                },
                .int, .comptime_int => {
                    return try std.fmt.parseInt(T, try self.readSymbols(), 10);
                },
                .float, .comptime_float => {
                    return try std.fmt.parseFloat(T, try self.readSymbols());
                },
                .@"enum", .enum_literal => {
                    const str = try self.readSymbols();
                    return std.meta.stringToEnum(T, str) orelse {
                        log.err("Wrong value {s} for the enum {s}", .{ str, @typeName(T) });
                        return error.WrongInput;
                    };
                },
                else => return error.WrongInput,
            }
        }

        fn readSymbols(self: *Self) Error![]const u8 {
            var capacity: usize = 0;
            while (true) {
                switch (try self.reader.next()) {
                    // Accumulate partial values.
                    .partial_number, .partial_string => |slice| {
                        @memmove(self.string_buffer[capacity .. capacity + slice.len], slice);
                        capacity += slice.len;
                    },
                    .partial_string_escaped_1 => |buf| {
                        @memmove(self.string_buffer[capacity .. capacity + buf.len], buf[0..]);
                        capacity += buf.len;
                    },
                    .partial_string_escaped_2 => |buf| {
                        @memmove(self.string_buffer[capacity .. capacity + buf.len], buf[0..]);
                        capacity += buf.len;
                    },
                    .partial_string_escaped_3 => |buf| {
                        @memmove(self.string_buffer[capacity .. capacity + buf.len], buf[0..]);
                        capacity += buf.len;
                    },
                    .partial_string_escaped_4 => |buf| {
                        @memmove(self.string_buffer[capacity .. capacity + buf.len], buf[0..]);
                        capacity += buf.len;
                    },
                    .number, .string => |slice| if (capacity == 0) {
                        return slice;
                    } else {
                        @memmove(self.string_buffer[capacity .. capacity + slice.len], slice);
                        capacity += slice.len;
                        return self.string_buffer[0..capacity];
                    },
                    else => {
                        return error.WrongInput;
                    },
                }
            }
        }
    };
}

fn assertEql(actual: anytype, expected: anytype) !void {
    if (u.isDebug()) {
        const act = switch (@typeInfo(@TypeOf(actual))) {
            .error_set, .error_union => try actual,
            else => actual,
        };
        switch (@typeInfo(@TypeOf(expected))) {
            .enum_literal => if (act != expected) {
                log.err("Expected {any}, but was {any}", .{ expected, act });
                return error.WrongInput;
            },
            else => if (!std.mem.eql(u8, act, expected)) {
                log.err("Expected {s}, but was {s}", .{ expected, act });
                return error.WrongInput;
            },
        }
    }
}

test "All components should be serializable" {
    var original_registry = try g.Registry.init(std.testing.allocator);
    errdefer original_registry.deinit();

    var inventory = try c.Inventory.empty(std.testing.allocator);
    try inventory.items.add(.{ .id = 7 });
    defer inventory.deinit();

    var pile = try c.Pile.empty(std.testing.allocator);
    try pile.items.add(.{ .id = 9 });
    defer pile.deinit();

    // Random components to check serialization:
    const expected = c.Components{
        .animation = c.Animation{ .preset = .hit },
        .description = c.Description{ .preset = .player },
        .door = c.Door{ .state = .opened },
        .equipment = c.Equipment{ .weapon = null, .light = .{ .id = 12 } },
        .health = c.Health{ .current = 42, .max = 100 },
        .initiative = c.Initiative{ .move_points = 5 },
        .inventory = inventory,
        .ladder = c.Ladder{ .id = .{ .id = 2 }, .direction = .down, .target_ladder = .{ .id = 3 } },
        .pile = pile,
        .position = c.Position{ .place = p.Point.init(12, 42) },
        .source_of_light = c.SourceOfLight{ .radius = 4 },
        .speed = c.Speed{ .move_points = 12 },
        .sprite = c.Sprite{ .codepoint = g.codepoints.human },
        .state = .walking,
        .weapon = c.Weapon{ .min_damage = 3, .max_damage = 32 },
        .z_order = c.ZOrder{ .order = .obstacle },
    };

    var buffer: [1024]u8 = @splat(0);
    var buffer_writer = std.io.fixedBufferStream(&buffer);
    const underlying_writer = buffer_writer.writer();
    var writer = Writer(@TypeOf(underlying_writer)).init(&original_registry, underlying_writer);

    // when:
    try writer.write(expected);
    original_registry.deinit();

    std.debug.print("{s}\n", .{buffer});

    // then:
    var actual_registry = try g.Registry.init(std.testing.allocator);
    defer actual_registry.deinit();

    var buffer_reader = std.io.fixedBufferStream(&buffer);
    const underlying_reader = buffer_reader.reader();
    var reader = Reader(@TypeOf(underlying_reader)).init(&actual_registry, underlying_reader);

    const actual = try reader.read(c.Components);

    try expectEql(expected, actual);
}

fn expectEql(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@TypeOf(expected), @TypeOf(actual));

    switch (@typeInfo(@TypeOf(expected))) {
        .pointer => try expectEql(expected.*, actual.*),
        .optional => if (expected == null)
            try std.testing.expectEqual(null, actual)
        else
            try expectEql(expected.?, actual.?),
        .@"struct" => |s| inline for (s.fields) |field| {
            if (@hasDecl(@TypeOf(expected), "eql")) {
                try std.testing.expect(expected.eql(actual));
            } else {
                try expectEql(@field(expected, field.name), @field(actual, field.name));
            }
        },
        else => try std.testing.expectEqual(expected, actual),
    }
}
