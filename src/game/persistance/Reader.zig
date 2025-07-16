const std = @import("std");
const g = @import("../game_pkg.zig");
const c = g.components;
const d = g.dungeon;
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.persistance_reader);

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
        pub fn read(self: *Self, comptime T: type) Error!T {
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
