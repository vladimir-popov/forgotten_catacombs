const std = @import("std");

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
