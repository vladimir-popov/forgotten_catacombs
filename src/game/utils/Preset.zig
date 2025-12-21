const std = @import("std");

const Type = std.builtin.Type;

/// Builds a static enum array with constant pointers to default values of fields of `S` with type `T`,
/// and all fields with same type of all inner structures.
/// It makes possible to get a constant value by its name known only in runtime,
/// and also it solves the issue with getting list of constants within a structure.
pub fn Preset(comptime T: type, S: type) type {
    const type_info = @typeInfo(S);
    switch (type_info) {
        .@"struct" => {},
        else => @compileError(std.fmt.comptimePrint(
            "Wrong `{s}` type. Expected struct, but found `{any}`",
            .{ @typeName(S), type_info },
        )),
    }
    const fields_count = fieldsCount(S, T);
    if (fields_count == 0)
        @compileError(std.fmt.comptimePrint(
            "To build a preset of {any} from {any} at least one field with type {any} should exist",
            .{ T, S, T },
        ));

    const all_fields = blk: {
        var acc: [fields_count]Type.StructField = undefined;
        _ = collectFields(&acc, S, T);
        break :blk acc;
    };

    const s_enum = blk: {
        var efs: [fields_count]Type.EnumField = undefined;
        for (all_fields, 0..) |field, i| {
            efs[i] = .{ .name = field.name, .value = i };
        }
        break :blk @Type(.{
            .@"enum" = .{
                .tag_type = std.math.IntFittingRange(0, efs.len - 1),
                .fields = &efs,
                .decls = &.{},
                .is_exhaustive = true,
            },
        });
    };

    return struct {
        pub const Tag = s_enum;

        pub const Iterator = struct {
            index: usize = 0,

            pub fn next(self: *Iterator) ?*const T {
                if (self.index < fields.values.len) {
                    defer self.index += 1;
                    return fields.values[self.index];
                } else {
                    return null;
                }
            }
        };

        pub fn iterator() Iterator {
            return .{};
        }

        pub const fields: std.EnumArray(Tag, *const T) = blk: {
            var map = std.EnumArray(Tag, *const T).initUndefined();
            for (all_fields, 0..) |field, i| {
                map.set(@enumFromInt(i), @ptrCast(@alignCast(field.default_value_ptr)));
            }
            break :blk map;
        };

        /// Returns a copy of the default value for the field `item`.
        pub inline fn get(item: Tag) T {
            return fields.get(item).*;
        }

        /// Gets an enum item, cast it to the string and then casts the string to the `T`.
        pub inline fn castByNameAndGet(item: anytype) *const T {
            return fields.get(std.meta.stringToEnum(Tag, @tagName(item)).?);
        }
    };
}

fn fieldsCount(comptime S: type, T: type) usize {
    const type_info = @typeInfo(S);
    if (type_info != .@"struct") return 0;

    var result = 0;
    for (type_info.@"struct".fields) |field| {
        if (std.meta.eql(field.type, T))
            result += 1;
    }
    for (type_info.@"struct".decls) |decl| {
        if (std.meta.hasFn(S, decl.name)) {
            continue;
        }
        result += fieldsCount(@field(S, decl.name), T);
    }
    return result;
}

fn collectFields(comptime all_fields: []Type.StructField, comptime S: type, T: type) usize {
    const type_info = @typeInfo(S);
    if (type_info != .@"struct") return 0;
    var result = 0;
    for (type_info.@"struct".fields) |field| {
        if (std.meta.eql(field.type, T)) {
            all_fields[result] = field;
            result += 1;
        }
    }
    for (type_info.@"struct".decls) |decl| {
        if (std.meta.hasFn(S, decl.name)) {
            continue;
        }
        result += collectFields(all_fields[result..], @field(S, decl.name), T);
    }
    return result;
}

test Preset {
    const p = Preset([]const u8, struct {
        foo: []const u8 = "Hello",
        bar: []const u8 = "world",
        boo: u8 = 0,
        pub const inner = struct {
            baz: []const u8 = "!",
        };
    });

    try std.testing.expectEqual(3, p.fields.values.len);
    try std.testing.expectEqualStrings("Hello", p.fields.get(.foo).*);
    try std.testing.expectEqualStrings("world", p.fields.get(.bar).*);
    try std.testing.expectEqualStrings("!", p.fields.get(.baz).*);
}
