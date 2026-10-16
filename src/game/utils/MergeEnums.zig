const std = @import("std");

/// Creates one enum containing all fields from the supplied enum types.
///
/// Fields keep the order of the input enum types and their declaration order.
/// The input enums must be non-empty, and their field names must be unique
/// across all inputs. The merged enum is generated at compile time and uses
/// the smallest integer type that can represent all of its tags.
///
/// ```zig
/// const Damage = MergeEnums(.{
///     enum { fire, acid },
///     enum { poison },
/// });
///
/// const damage: Damage = .poison;
/// ```
pub fn MergeEnums(comptime enums: anytype) type {
    comptime {
        var field_count: usize = 0;

        for (enums) |E| {
            const info = @typeInfo(E);
            if (info != .@"enum") {
                @compileError("MergeEnums expects only enum types");
            }

            field_count += info.@"enum".fields.len;
        }

        const TagInt = std.math.IntFittingRange(0, field_count - 1);
        var names: [field_count][]const u8 = undefined;
        var values: [field_count]TagInt = undefined;
        var i = 0;
        for (enums) |E| {
            const enum_info = @typeInfo(E).@"enum";

            for (enum_info.fields) |field| {
                names[i] = field.name;
                values[i] = i;
                i += 1;
            }
        }

        return @Enum(
            TagInt,
            std.builtin.Type.Enum.Mode.exhaustive,
            &names,
            &values,
        );
    }
}

test MergeEnums {
    const E = MergeEnums(.{
        enum { a, b },
        enum { c, d },
    });
    const a: [4]E = .{ .a, .b, .c, .d };
    _ = a;
}
