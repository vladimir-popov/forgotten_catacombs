const std = @import("std");

const Type = std.builtin.Type;

/// Builds a static enum array with constant pointers to default values of fields of S with type T,
/// and all fields of all inner structures.
/// It makes possible to get a constant value by its name known only in runtime.
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

    const fields = blk: {
        var acc: [fields_count]Type.StructField = undefined;
        _ = collectFields(&acc, S, T);
        break :blk acc;
    };

    const s_enum = blk: {
        var efs: [fields_count]Type.EnumField = undefined;
        for (fields, 0..) |field, i| {
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
                if (self.index < values.values.len) {
                    defer self.index += 1;
                    return values.values[self.index];
                } else {
                    return null;
                }
            }
        };

        pub fn iterator() Iterator {
            return .{};
        }

        pub const values: std.EnumArray(Tag, *const T) = blk: {
            var map = std.EnumArray(Tag, *const T).initUndefined();
            for (fields, 0..) |field, i| {
                map.set(@enumFromInt(i), @ptrCast(@alignCast(field.default_value_ptr)));
            }
            break :blk map;
        };
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

    try std.testing.expectEqual(3, p.values.values.len);
    try std.testing.expectEqualStrings("Hello", p.values.get(.foo).*);
    try std.testing.expectEqualStrings("world", p.values.get(.bar).*);
    try std.testing.expectEqualStrings("!", p.values.get(.baz).*);
}
