const std = @import("std");

const Type = std.builtin.Type;

/// Builds a static string map with constant pointers to default values of fields of S.
/// All fields must have a same type and default value.
/// It makes possible to get a constant value by its name known only in runtime.
pub fn Preset(comptime S: type) type {
    const type_info = @typeInfo(S);
    switch (type_info) {
        .@"struct" => {},
        else => @compileError(std.fmt.comptimePrint(
            "Wrong `{s}` type. Expected struct, but found `{any}`",
            .{ @typeName(S), type_info },
        )),
    }
    const struct_fields = type_info.@"struct".fields;
    if (struct_fields.len == 0) {
        @compileError("At least one field should be specified");
    }
    const T = typeOfTheFirstField(S);
    for (struct_fields) |field| {
        if (!std.meta.eql(field.type, T))
            @compileError(std.fmt.comptimePrint(
                "Wrong type of the field {s}. Expected {s}, but found {s}",
                .{ field.name, @typeName(T), @typeName(field.type) },
            ));
    }

    const KV = struct { []const u8, *const T };
    comptime var kvs: [struct_fields.len]KV = undefined;
    inline for (struct_fields, 0..) |field, i| {
        kvs[i] = .{ field.name, @ptrCast(@alignCast(field.default_value_ptr)) };
    }
    const stringMap = std.StaticStringMap(*const T).initComptime(&kvs);

    return struct {
        pub const Tag = std.meta.FieldEnum(S);

        pub const size: usize = @typeInfo(Tag).@"enum".fields.len;

        /// Returns default value for the field appropriate to the passed `tag`.
        pub fn get(tag: Tag) *const T {
            return stringMap.get(@tagName(tag)).?;
        }

        pub fn all() [size]*const T {
            var result: [size]*const T = undefined;
            for (std.meta.tags(Tag), 0..) |tag, i| {
                result[i] = get(tag);
            }
            return result;
        }
    };
}

fn typeOfTheFirstField(comptime S: type) type {
    const type_info = @typeInfo(S);
    const struct_fields = type_info.@"struct".fields;
    return struct_fields[0].type;
}

test Preset {
    const p = Preset(struct {
        foo: []const u8 = "Hello",
        bar: []const u8 = "world",
    });

    try std.testing.expectEqualStrings("Hello", p.get(.foo).*);
    try std.testing.expectEqualStrings("world", p.get(.bar).*);
}
