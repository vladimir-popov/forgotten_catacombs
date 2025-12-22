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

    var names: [struct_fields.len][]const u8 = undefined;
    var types: [struct_fields.len]type = undefined;
    var attrs: [struct_fields.len]Type.StructField.Attributes = undefined;
    // every field inside the ComponentsStruct should be optional, but we need their child types
    for (struct_fields, 0..) |field, i| {
        switch (@typeInfo(field.type)) {
            .optional => |opt| {
                names[i] = @typeName(opt.child);
                types[i] = ArraySet(opt.child);
                attrs[i] = .{
                    .@"align" = @alignOf(ArraySet(opt.child)),
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

    return @Struct(
        .auto,
        null,
        names[0..],
        &types,
        &attrs,
    );
}
