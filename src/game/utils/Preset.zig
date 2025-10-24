const std = @import("std");

const Type = std.builtin.Type;

/// Builds a static enum array with constant pointers to default values of fields of S.
/// All fields must have the same type T and a default value.
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
    const struct_fields = type_info.@"struct".fields;
    if (struct_fields.len == 0) {
        @compileError("At least one field should be specified");
    }
    for (struct_fields) |field| {
        if (!std.meta.eql(field.type, T))
            @compileError(std.fmt.comptimePrint(
                "Wrong type of the field {s}. Expected {s}, but found {s}",
                .{ field.name, @typeName(T), @typeName(field.type) },
            ));
    }

    return struct {
        pub const Tag = std.meta.FieldEnum(S);

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
            for (struct_fields, 0..) |field, i| {
                map.set(@enumFromInt(i), @ptrCast(@alignCast(field.default_value_ptr)));
            }
            break :blk map;
        };
    };
}

test Preset {
    const p = Preset([]const u8, struct {
        foo: []const u8 = "Hello",
        bar: []const u8 = "world",
    });

    try std.testing.expectEqualStrings("Hello", p.values.get(.foo).*);
    try std.testing.expectEqualStrings("world", p.values.get(.bar).*);
}
