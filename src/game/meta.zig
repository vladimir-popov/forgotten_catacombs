//! Set of helper to get information from the registry.
const std = @import("std");
const g = @import("game_pkg.zig");
const c = g.components;

pub fn name(registry: g.Registry, entity: g.Entity) []const u8 {
    return if (registry.get(entity, c.Description)) |description|
        g.descriptions.Presets.get(description.preset).name
    else
        "";
}

pub fn isEnemy(registry: g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.EnemyState);
}

pub fn isItem(registry: g.Registry, entity: g.Entity) bool {
    return registry.has(entity, c.Weight);
}

pub fn canEquip(registry: g.Registry, item: g.Entity) bool {
    return isItem(registry, item) and
        (registry.has(item, c.Damage) or registry.has(item, c.SourceOfLight));
}

pub fn getSourceOfLight(registry: g.Registry, equipment: *const c.Equipment) ?*c.SourceOfLight {
    if (equipment.right_hand) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol;
        }
    }
    if (equipment.left_hand) |id| {
        if (registry.get(id, c.SourceOfLight)) |sol| {
            return sol;
        }
    }
    return null;
}

pub fn getWeapon(registry: g.Registry, equipment: *const c.Equipment) ?struct{g.Entity, *c.Damage} {
    if (equipment.right_hand) |id| {
        if (registry.get(id, c.Damage)) |damage| {
            return .{id, damage};
        }
    }
    if (equipment.left_hand) |id| {
        if (registry.get(id, c.Damage)) |damage| {
            return .{id, damage};
        }
    }
    return null;
}

pub fn describe(
    registry: g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    is_known: bool,
    dev_mode: bool,
    text_area: *g.windows.TextArea,
) !void {
    const description = if (registry.get(entity, c.Description)) |descr|
        g.descriptions.Presets.get(descr.preset).description
    else
        &.{};
    for (description) |str| {
        var line = try text_area.addEmptyLine(alloc);
        @memmove(line[0..str.len], str);
    }
    _ = try text_area.addEmptyLine(alloc);
    if (dev_mode or is_known) {
        try describeStats(registry, alloc, entity, text_area, 1);
    }
}

fn describeStats(
    registry: g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
    pad: usize,
) !void {
    if (registry.get(entity, c.Damage)) |damage| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(
            line[pad..],
            "Damage: {t} {d}-{d}",
            .{ damage.damage_type, damage.min, damage.max },
        );
    }
    if (registry.get(entity, c.Effect)) |effect| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(
            line[pad..],
            "Effect: {t} {d}-{d}",
            .{ effect.effect_type, effect.min, effect.max },
        );
    }
    if (registry.get(entity, c.SourceOfLight)) |light| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[pad..], "Radius of light: {d}", .{light.radius});
    }
    if (registry.get(entity, c.Weight)) |weight| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[pad..], "Weight: {d}", .{weight.value});
    }
}

fn describeEnemy(
    registry: g.Registry,
    alloc: std.mem.Allocator,
    entity: g.Entity,
    text_area: *g.windows.TextArea,
) !void {
    if (registry.get(entity, c.Health)) |health| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Health: {d}/{d}", .{ health.current, health.max });
    }
    if (registry.get(entity, c.Speed)) |speed| {
        var line = try text_area.addEmptyLine(alloc);
        _ = try std.fmt.bufPrint(line[1..], "Speed: {d}", .{speed.move_points});
    }
    if (registry.get(entity, c.Equipment)) |equipment| {
        if (equipment.right_hand) |right_hand| {
            var line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "In right hand: {s}", .{g.meta.name(registry, right_hand)});
            try describeStats(alloc, right_hand, text_area, 3);
        }
        if (equipment.right_hand) |left_hand| {
            var line = try text_area.addEmptyLine(alloc);
            _ = try std.fmt.bufPrint(line[1..], "In left hand: {s}", .{g.meta.name(registry, left_hand)});
            try describeStats(alloc, left_hand, text_area, 3);
        }
    }
}
