//! A set of comptime functions to verify a set of components for entities according to their archetype.
const std = @import("std");
const builtin = @import("builtin");
const g = @import("../game_pkg.zig");
const c = g.components;

inline fn defined(components: c.Components, comptime field: []const u8) void {
    if (@field(components, field) == null)
        @compileError(std.fmt.comptimePrint(
            "Field '{s}' is not defined for {t}",
            .{ field, components.description.?.preset },
        ));
}

/// Checks that components have a relevant to `E` preset of description.
inline fn hasType(comptime E: type, components: c.Components) void {
    if (std.meta.stringToEnum(E, @tagName(components.description.?.preset)) == null) {
        @compileError(std.fmt.comptimePrint(
            "{s} doesn't have expected type {s}",
            .{ @tagName(components.description.?.preset), @typeName(E) },
        ));
    }
}

pub fn enemy(components: c.Components) c.Components {
    comptime {
        defined(components, "armor");
        defined(components, "description");
        defined(components, "experience");
        defined(components, "stats");
        defined(components, "skills");
        defined(components, "health");
        defined(components, "initiative");
        defined(components, "speed");
        defined(components, "sprite");
        defined(components, "state");
        hasType(g.meta.EnemyType, components);
        return components;
    }
}

pub inline fn item(components: c.Components) c.Components {
    comptime {
        defined(components, "description");
        defined(components, "price");
        defined(components, "rarity");
        defined(components, "sprite");
        defined(components, "weight");
        return components;
    }
}

pub inline fn food(components: c.Components) c.Components {
    comptime {
        _ = item(components);
        defined(components, "consumable");
        std.debug.assert(components.consumable.?.consumable_type == .food);
        return components;
    }
}

pub inline fn armor(components: c.Components) c.Components {
    comptime {
        _ = item(components);
        defined(components, "armor");
        return components;
    }
}

pub inline fn weapon(components: c.Components) c.Components {
    comptime {
        _ = item(components);
        defined(components, "effects");
        defined(components, "weapon_class");
        return components;
    }
}

pub inline fn potion(components: c.Components) c.Components {
    comptime {
        _ = item(components);
        hasType(g.meta.PotionType, components);
        defined(components, "consumable");
        std.debug.assert(components.consumable.?.consumable_type == .potion);
        return components;
    }
}
