const std = @import("std");
const g = @import("../game_pkg.zig");
const p = g.primitives;
const u = g.utils;

const log = std.log.scoped(.persistance_writer);

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

        pub fn write(self: *Self, value: anytype) Error!void {
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
