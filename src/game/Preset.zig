const std = @import("std");
const Type = std.builtin.Type;

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
        pub const Keys = StructFields(S);

        pub fn get(key: Keys) *const T {
            return stringMap.get(@tagName(key)).?;
        }
    };
}

fn typeOfTheFirstField(comptime S: type) type {
    const type_info = @typeInfo(S);
    const struct_fields = type_info.@"struct".fields;
    return struct_fields[0].type;
}

fn StructFields(comptime S: type) type {
    const type_info = @typeInfo(S);
    const struct_fields = type_info.@"struct".fields;
    var values: [struct_fields.len]Type.EnumField = undefined;
    for (struct_fields, 0..) |field, i| {
        values[i] = .{ .name = field.name, .value = i };
    }
    return @Type(.{ .@"enum" = .{
        .fields = &values,
        .decls = &[_]std.builtin.Type.Declaration{},
        .tag_type = u8,
        .is_exhaustive = true,
    } });
}

test Preset {
    const p = Preset(struct {
        foo: []const u8 = "Hello",
        bar: []const u8 = "world",
    });

    try std.testing.expectEqualStrings("Hello", p.get(.foo).*);
    try std.testing.expectEqualStrings("world", p.get(.bar).*);
}
