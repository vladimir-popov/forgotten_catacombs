const std = @import("std");
const builtin = @import("builtin");
const g = @import("../game_pkg.zig");
const c = g.components;

inline fn defined(components: c.Components, comptime field: []const u8) void {
    if (@field(components, field) == null)
        std.debug.panic("Field '{s}' is not defined:\n{any}", .{ field, components });
}

pub fn enemy(components: c.Components) c.Components {
    if (builtin.mode == .Debug) {
        defined(components, "description");
        defined(components, "sprite");
        defined(components, "health");
        defined(components, "speed");
        defined(components, "initiative");
        defined(components, "state");
    }
    return components;
}

pub fn item(components: c.Components) c.Components {
    if (builtin.mode == .Debug) {
        defined(components, "description");
        defined(components, "sprite");
        defined(components, "weight");
        defined(components, "price");
    }
    return components;
}

pub fn weapon(components: c.Components) c.Components {
    if (builtin.mode == .Debug) {
        _ = item(components);
        defined(components, "damage");
    }
    return components;
}

pub fn potion(components: c.Components) c.Components {
    if (builtin.mode == .Debug) {
        _ = item(components);
        defined(components, "consumable");
        std.debug.assert(components.consumable.?.consumable_type == .potion);
    }
    return components;
}
