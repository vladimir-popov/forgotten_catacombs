const std = @import("std");
const Type = std.builtin.Type;
const Entity = @import("Entity.zig");
const ArraySet = @import("ArraySet.zig").ArraySet;

/// Generated in compile time structure,
/// which has ArraySet for every type from the `ComponentsStruct`.
pub fn ComponentsMap(comptime ComponentsStruct: anytype) type {
    const type_info = @typeInfo(ComponentsStruct);
    switch (type_info) {
        .@"struct" => {},
        else => @compileError(
            std.fmt.comptimePrint(
                "Wrong `{s}` type. The components must be grouped to the struct with optional types, but found `{any}`",
                .{ @typeName(ComponentsStruct), type_info },
            ),
        ),
    }
    const struct_fields = type_info.@"struct".fields;
    if (struct_fields.len == 0) {
        @compileError("At least one component should exist");
    }

    var components: [struct_fields.len]Type.StructField = undefined;
    // every field inside the ComponentsStruct should be optional, but we need their child types
    for (struct_fields, 0..) |field, i| {
        switch (@typeInfo(field.type)) {
            .optional => |opt| {
                components[i] = .{
                    .name = @typeName(opt.child),
                    .type = ArraySet(opt.child),
                    .default_value_ptr = null,
                    .is_comptime = false,
                    .alignment = @alignOf(ArraySet(opt.child)),
                };
            },
            else => {
                @compileError(std.fmt.comptimePrint(
                    "All fields in the `{s}` should be optional, but the `{s}: {any}` is not.",
                    .{ @typeName(ComponentsStruct), field.name, field.type },
                ));
            },
        }
    }

    return @Type(.{
        .@"struct" = .{
            .layout = .auto,
            .fields = components[0..],
            .decls = &[_]std.builtin.Type.Declaration{},
            .is_tuple = false,
        },
    });
}
