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

pub const SESSION_FILE_NAME = "session.json";

pub fn pathToLevelFile(buf: []u8, depth: u8) ![]const u8 {
    return try std.fmt.bufPrint(buf, "level_{d}.json", .{depth});
}

pub const Writer = struct {
    const Self = @This();

    pub const Error = anyerror;

    // used to get components of entities inside containers such as pile or inventory
    registry: *const g.Registry,
    writer: std.json.Stringify,

    pub fn init(registry: *const g.Registry, writer: *std.io.Writer) Self {
        return .{
            .registry = registry,
            .writer = .{ .writer = writer, .options = .{ .emit_null_optional_fields = false } },
        };
    }

    pub fn beginObject(self: *Self) Error!void {
        try self.writer.beginObject();
    }

    pub fn endObject(self: *Self) Error!void {
        try self.writer.endObject();
    }

    pub fn writeEntity(self: *Self, entity: g.Entity) Error!void {
        try self.beginObject();
        try self.writeNumericKey(entity.id);
        try self.write(try self.registry.entityToStruct(entity));
        try self.endObject();
    }

    pub fn write(self: *Self, value: anytype) Error!void {
        const T = @TypeOf(value);
        if (std.meta.hasMethod(T, "save")) {
            try value.save(self);
            return;
        }
        switch (@typeInfo(T)) {
            .bool, .int, .float, .comptime_int, .comptime_float, .@"enum", .enum_literal => {
                try self.writer.write(value);
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
            } else {
                try self.write(value.*);
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
                        }
                    }
                    try self.endObject();
                } else {
                    log.err("Untagged unions are not supported. {s}", .{@typeName(T)});
                    return error.UnsupportedType;
                }
            },
            else => {
                log.err("Unsupported type for serialization: {s}.", .{@typeName(T)});
                return error.UnsupportedType;
            },
        }
    }

    pub fn beginCollection(self: *Self) Error!void {
        try self.writer.beginArray();
    }

    pub fn endCollection(self: *Self) Error!void {
        try self.writer.endArray();
    }

    pub fn writeStringKey(self: *Self, name: []const u8) Error!void {
        try self.writer.objectField(name);
    }

    pub fn writeNumericKey(self: *Self, key: anytype) Error!void {
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
};

pub const Reader = struct {
    const Self = @This();
    pub const Error = anyerror;

    registry: *g.Registry,
    json_reader: std.json.Reader,

    pub fn init(registry: *g.Registry, reader: *std.io.Reader) Self {
        return .{
            .registry = registry,
            .json_reader = .init(registry.allocator(), reader),
        };
    }

    pub fn deinit(self: *Self) void {
        self.json_reader.deinit();
    }

    pub fn beginObject(self: *Self) Error!void {
        try assertEql(self.json_reader.next(), .object_begin);
    }

    pub fn endObject(self: *Self) Error!void {
        try assertEql(self.json_reader.next(), .object_end);
    }

    pub fn readEntity(self: *Self) anyerror!g.Entity {
        var buf: [128]u8 = undefined;
        try self.beginObject();
        const entity = g.Entity{ .id = try self.readKeyAsNumber(g.Entity.IdType, &buf) };
        const components = self.read(c.Components) catch |err| {
            log.err("Error on reading components of the entity {d}", .{entity.id});
            return err;
        };
        try self.registry.setComponentsToEntity(entity, components);
        try self.endObject();
        return entity;
    }

    // registry is used in case of EntitiesSet, to store the components during deserialization.
    pub fn read(self: *Self, comptime T: type) Error!T {
        if (std.meta.hasMethod(T, "load")) {
            return try T.load(self);
        }
        switch (@typeInfo(T)) {
            .void => {
                try self.beginObject();
                try self.endObject();
                return {};
            },
            .bool => {
                const next = try self.json_reader.next();
                return if (next == .true) true else if (next == .false) false else {
                    log.err("Wrong input. Expected bool, but was {any}", .{next});
                    return error.WrongInput;
                };
            },
            .int, .comptime_int => {
                var buf: [32]u8 = undefined;
                return try std.fmt.parseInt(T, try self.readBytes(&buf), 10);
            },
            .float, .comptime_float => {
                var buf: [32]u8 = undefined;
                return try std.fmt.parseFloat(T, try self.readBytes(&buf));
            },
            .@"enum", .enum_literal => {
                var buf: [32]u8 = undefined;
                const str = try self.readBytes(&buf);
                return std.meta.stringToEnum(T, str) orelse {
                    log.err("Wrong value {s} for the enum {s}", .{ str, @typeName(T) });
                    return error.WrongInput;
                };
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
                var buf: std.ArrayListUnmanaged(ptr.child) = .empty;
                errdefer buf.deinit(self.registry.allocator());

                try self.beginCollection();
                while (!try self.isCollectionEnd()) {
                    const item = buf.addOne(self.registry.allocator());
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
                    if (key == null and !try self.isObjectEnd()) {
                        var buf: [128]u8 = undefined;
                        key = try self.readKeyAsString(&buf);
                    }
                    if (key != null and std.mem.eql(u8, field.name, key.?)) {
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
                const key = try self.readKeyAsString();
                inline for (un.fields) |u_field| {
                    if (std.mem.eql(u8, u_field.name, key)) {
                        const value = try self.read(u_field.type);
                        try self.endObject();
                        return @unionInit(T, u_field.name, value);
                    }
                }
            },
            else => {},
        }
        log.err("Unsupported type for desrialization {s}", .{@typeName(T)});
        return error.UnsupportedType;
    }

    pub fn isObjectEnd(self: *Self) Error!bool {
        return try self.json_reader.peekNextTokenType() == .object_end;
    }

    pub fn beginCollection(self: *Self) Error!void {
        try assertEql(self.json_reader.next(), .array_begin);
    }

    pub fn endCollection(self: *Self) Error!void {
        try assertEql(self.json_reader.next(), .array_end);
    }

    pub fn isCollectionEnd(self: *Self) Error!bool {
        return try self.json_reader.peekNextTokenType() == .array_end;
    }

    pub fn readKey(self: *Self, expected: []const u8) Error![]const u8 {
        var buf: [128]u8 = undefined;
        const key = try self.readBytes(&buf);
        try assertEql(key, expected);
        return expected;
    }

    pub fn readKeyAsString(self: *Self, buffer: []u8) Error![]const u8 {
        return try self.readBytes(buffer);
    }

    pub fn readKeyAsNumber(self: *Self, comptime N: type, buffer: []u8) Error!N {
        return try std.fmt.parseInt(N, try self.readKeyAsString(buffer), 10);
    }

    pub fn readBytes(self: *Self, buffer: []u8) Error![]const u8 {
        var capacity: usize = 0;
        while (true) {
            switch (try self.json_reader.next()) {
                // Accumulate partial values.
                .partial_number, .partial_string => |slice| {
                    @memmove(buffer[capacity .. capacity + slice.len], slice);
                    capacity += slice.len;
                },
                .partial_string_escaped_1 => |buf| {
                    @memmove(buffer[capacity .. capacity + buf.len], buf[0..]);
                    capacity += buf.len;
                },
                .partial_string_escaped_2 => |buf| {
                    @memmove(buffer[capacity .. capacity + buf.len], buf[0..]);
                    capacity += buf.len;
                },
                .partial_string_escaped_3 => |buf| {
                    @memmove(buffer[capacity .. capacity + buf.len], buf[0..]);
                    capacity += buf.len;
                },
                .partial_string_escaped_4 => |buf| {
                    @memmove(buffer[capacity .. capacity + buf.len], buf[0..]);
                    capacity += buf.len;
                },
                .number, .string => |slice| if (capacity == 0) {
                    return slice;
                } else {
                    @memmove(buffer[capacity .. capacity + slice.len], slice);
                    capacity += slice.len;
                    return buffer[0..capacity];
                },
                else => |unexpected| {
                    log.err("Unexpected input during reading symbols: {any}", .{unexpected});
                    return error.WrongInput;
                },
            }
        }
    }
};

fn assertEql(actual: anytype, expected: anytype) !void {
    if (comptime !u.isDebug()) return;

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

test "All components should be serializable" {
    var original_registry = try g.Registry.init(std.testing.allocator);
    errdefer original_registry.deinit();

    var inventory = try c.Inventory.empty(std.testing.allocator);
    try inventory.items.add(.{ .id = 7 });
    defer inventory.deinit();

    var pile = try c.Pile.empty(std.testing.allocator);
    try pile.items.add(.{ .id = 9 });
    defer pile.deinit();

    var shop: c.Shop = try .empty(std.testing.allocator, 1.2, 42);
    defer shop.deinit();

    // Random components to check serialization:
    const expected = c.Components{
        .animation = c.Animation{ .preset = .hit },
        .consumable = .{ .calories = 12, .consumable_type = .food },
        .damage = .{ .damage_type = .cutting, .min = 1, .max = 2 },
        .description = c.Description{ .preset = .player },
        .door = c.Door{ .state = .opened },
        .effect = .{ .min = 1, .max = 3, .effect_type = .burning },
        .equipment = c.Equipment{ .weapon = null, .light = .{ .id = 12 } },
        .health = c.Health{ .current = 42, .max = 100 },
        .initiative = c.Initiative{ .move_points = 5 },
        .inventory = inventory,
        .ladder = c.Ladder{ .id = .{ .id = 2 }, .direction = .down, .target_ladder = .{ .id = 3 } },
        .pile = pile,
        .price = .{ .value = 100 },
        .position = c.Position{ .place = p.Point.init(12, 42), .zorder = .item },
        .shop = shop,
        .source_of_light = c.SourceOfLight{ .radius = 4 },
        .speed = c.Speed{ .move_points = 12 },
        .sprite = c.Sprite{ .codepoint = g.codepoints.human },
        .state = .walking,
        .wallet = .{ .money = 321 },
        .weight = .{ .value = 55 },
    };

    inline for (@typeInfo(c.Components).@"struct".fields) |field| {
        if (@field(expected, field.name) == null) {
            log.err("A component {s} is not defined.", .{field.name});
            return error.ComponentIsNotDefined;
        }
    }

    var buffer: [4048]u8 = @splat(0);
    var fixed_writer = std.io.Writer.fixed(&buffer);
    var writer = Writer.init(&original_registry, &fixed_writer);

    // when:
    try writer.write(expected);
    original_registry.deinit();

    // then:
    var actual_registry = try g.Registry.init(std.testing.allocator);
    defer actual_registry.deinit();

    var fixed_reader = std.io.Reader.fixed(&buffer);
    var reader = Reader.init(&actual_registry, &fixed_reader);

    const actual = reader.read(c.Components) catch |err| {
        std.debug.print("Generated json:\n{s}\n", .{&buffer});
        return err;
    };

    expectEql(expected, actual) catch |err| {
        std.debug.print("Generated json:\n{s}\n", .{buffer});
        std.debug.print("Actual components:\n{any}\n", .{actual});
        return err;
    };
}

fn expectEql(expected: anytype, actual: anytype) !void {
    try std.testing.expectEqual(@TypeOf(expected), @TypeOf(actual));

    if (std.meta.hasMethod(@TypeOf(expected), "append")) {
        return std.testing.expectEqual(expected, actual);
    }

    switch (@typeInfo(@TypeOf(expected))) {
        .pointer => try expectEql(expected.*, actual.*),
        .optional => if (expected == null)
            try std.testing.expectEqual(null, actual)
        else if (actual) |value|
            try expectEql(expected.?, value)
        else
            std.debug.panic("Expected value {any}, but was null", .{expected.?}),
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
